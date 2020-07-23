function assimilate!(
	agents::AbstractArray,
	acting_agent::Agent,
	interaction_partner::Agent
)

	random_attr = rand(1:length(acting_agent.cultureVector))

	if acting_agent.cultureVector[random_attr] - interaction_partner.cultureVector[random_attr] != 0
		acting_agent.cultureVector[random_attr] = interaction_partner.cultureVector[random_attr]
	else
		assimilate!(agents, acting_agent, interaction_partner)
	end

	return acting_agent

end

function create_network(nettopology::Int64, agentcount::Int64, networkprops::Dict)
	if nettopology == 1
		try
			height = Int(networkprops["grid_height"])
			width = Int(agentcount / height)
			network = grid([height, width])
		catch
			print(
				"""
				No/Faulty grid height provided
				defaulting to grid with dimensions [agentcount, 1]
				"""
			)
			network = grid(Int64[agentcount, 1])
		end
	elseif nettopology == 2
		network = erdos_renyi(agentcount, networkprops["p"])
	elseif nettopology == 3
		network = watts_strogatz(agentcount, networkprops["k"], networkprops["beta"])
	elseif nettopology == 4
		network = barabasi_albert(agentcount, networkprops["m0"])
	elseif nettopology == 5
		network = complete_graph(agentcount)
	else
		try
			height = Int(networkprops["grid_height"])
			width = Int(agentcount / height)
			network = grid([height, width])
		catch
			network = grid(Int64[agentcount, 1])
		end
		print(
			"""
			irregular input for nettopology
			defaulting to grid
			choose one of the following to specify network topology:
			- nettopology=1 (grid graph)
			- nettopology=2 (erdos-renyi graph)
			- nettopology=3 (watts-strogatz graph)
			- nettopology=4 (barabasi-albert graph)
			- nettopology=5 (complete graph)
			"""
		)
	end
	return network
end

function tick!(
	agents::AbstractArray,
	network::AbstractGraph
)

	random_draw = rand(1:length(agents))
	acting_agent = agents[random_draw]

	interaction_partner = agents[rand(neighbors(network, random_draw))]

	if !acting_agent.socialbot

		similarity = sum(
			[
				i == j
				for (i, j) in zip(
					acting_agent.cultureVector,
					interaction_partner.cultureVector
				)
			]
		) / length(acting_agent.cultureVector)

		if rand() < similarity && similarity != 1
			assimilate!(agents, acting_agent, interaction_partner)
		end
	end

	return (network, agents)
end

function run(
	;
	agentcount::Int64=100,
	n_iter::Int64=1000,
	nettopology::Int64=1,
	networkprops::Dict=Dict(),
	socialbotfrac::Float64=0.00,
	rndseed::Int64=1,
	repcount::Int64=1,
	export_every_n::Int64=100
)

	Random.seed!(MersenneTwister(rndseed))

	networks = Dict{Int64, AbstractGraph}()
	data = Dict{Int64, DataFrame}()

	for rep in 1:repcount

		df = DataFrame(
			TickNr = Int64[],
			AgentID = Int64[],
			CultureTmp = Any[]
		)

		agents = Agent[]

		for i in 1:round(Int64, (1 - socialbotfrac) * agentcount)
			push!(agents, Agent(rand(0:9, 5)))
		end

		realagents = length(agents)

		for i in 1:(agentcount - realagents)
			push!(agents, Agent(fill(0, 5), true))
		end

		network = create_network(nettopology, agentcount, networkprops)
		networks[rep] = network

		state = Tuple{AbstractGraph, Array{Agent, 1}}[]

		for i in 1:n_iter
			tick!(agents, network)
			if i % export_every_n == 0
				append!(
					df,
					DataFrame(
						TickNr = i,
						AgentID = 1:length(agents),
						CultureTmp = [agent.cultureVector for agent in agents]
					)
				)
			end

		end  # end iter

		data[rep] = df

		print(".")

	end  # end rep

	return (data, networks)

end

function export_experiment(;
	experiment,
	path::String="",
	socialbotfrac::Float64=0.0,
	networkprops::Dict=Dict(),
	aggregated::Bool=true
)

    # create data directory
    if !("data" in readdir(path))
        mkdir(joinpath(path, "data"))
    end

    # export graphs to edge list format
    for key in keys(experiment[2])
        if !("graphs" in readdir(joinpath(path, "data")))
            mkdir(joinpath(path, "data", "graphs"))
        end
        savegraph(
            joinpath(path, "data", "graphs", "rep_" * string(key) * ".txt"),
            experiment[2][key],
            GraphIO.EdgeList.EdgeListFormat()
        )
    end

    # unpack culture vector for data exchange
    function reshape_df!(df)
        df[!, "Culture"] = [join(c) for c in df[!, "CultureTmp"]]
		select!(df, DataFrames.Not(:CultureTmp))
        return df
    end
    for key in keys(experiment[1])
        reshape_df!(experiment[1][key])
    end

	if aggregated
		agg_df = DataFrame(
			Rep = Int64[],
			Size = Int64[],
			Culture = String[]
		)
		for key in keys(experiment[1])
			df = experiment[1][key]
			finaltick = filter(:TickNr => ==(maximum(df[!, "TickNr"])), df)
			rep = key
			unique_cultures = unique(finaltick[!, "Culture"])
			for c in unique_cultures
				push!(
					agg_df,
					(
						rep,
						sum([culture == c for culture in finaltick[!, "Culture"]]),
						c
					)
				)
			end
		end
		agg_df[!, "SocialBotFrac"] .= socialbotfrac
		for k in keys(networkprops)
			agg_df[!, k] .= networkprops[k]
		end
		if !("agents" in readdir(joinpath(path, "data")))
			mkdir(joinpath(path, "data", "agents"))
		end
		Feather.write(joinpath(path, "data", "agents", "adata.feather"), agg_df)
	else
	    # export entire data
	    for key in keys(experiment[1])
	        if !("agents" in readdir(joinpath(path, "data")))
	            mkdir(joinpath(path, "data", "agents"))
	        end
	        Feather.write(joinpath(path, "data", "agents", "rep_" * string(key) * ".feather"), experiment[1][key])
	    end
	end

end
