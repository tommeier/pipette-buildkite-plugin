defmodule Pipette.Graph do
  @moduledoc """
  Directed Acyclic Graph (DAG) for pipeline dependency management.

  Builds a dependency graph from groups and steps, supports cycle
  detection, and computes transitive dependencies (ancestors).

  ## Example

      groups = [
        %Pipette.Group{name: :lint, steps: []},
        %Pipette.Group{name: :test, depends_on: :lint, steps: []},
        %Pipette.Group{name: :deploy, depends_on: :test, steps: []}
      ]

      graph = Pipette.Graph.from_groups(groups)
      Pipette.Graph.acyclic?(graph)          #=> true
      Pipette.Graph.ancestors(graph, :deploy) #=> MapSet.new([:test, :lint])
  """

  defstruct nodes: MapSet.new(), edges: %{}

  @type node_id :: atom() | {atom(), atom()}
  @type t :: %__MODULE__{
          nodes: MapSet.t(node_id()),
          edges: %{node_id() => MapSet.t(node_id())}
        }

  @doc "Create an empty graph."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Add a node to the graph. Returns the graph unchanged if the node already exists."
  @spec add_node(t(), node_id()) :: t()
  def add_node(%__MODULE__{} = graph, node) do
    %{graph | nodes: MapSet.put(graph.nodes, node)}
  end

  @doc "Add a directed edge from `from` to `to`. Both nodes are added if not present."
  @spec add_edge(t(), node_id(), node_id()) :: t()
  def add_edge(%__MODULE__{} = graph, from, to) do
    graph = add_node(graph, from)
    graph = add_node(graph, to)
    edges = Map.update(graph.edges, from, MapSet.new([to]), &MapSet.put(&1, to))
    %{graph | edges: edges}
  end

  @doc "Check if a node exists in the graph."
  @spec has_node?(t(), node_id()) :: boolean()
  def has_node?(%__MODULE__{} = graph, node) do
    MapSet.member?(graph.nodes, node)
  end

  @doc "Check if a directed edge exists from `from` to `to`."
  @spec has_edge?(t(), node_id(), node_id()) :: boolean()
  def has_edge?(%__MODULE__{} = graph, from, to) do
    case Map.get(graph.edges, from) do
      nil -> false
      targets -> MapSet.member?(targets, to)
    end
  end

  @doc "Return all edges as a list of `{from, to}` tuples."
  @spec edges(t()) :: [{node_id(), node_id()}]
  def edges(%__MODULE__{} = graph) do
    Enum.flat_map(graph.edges, fn {from, targets} ->
      Enum.map(targets, fn to -> {from, to} end)
    end)
  end

  @doc """
  Build a dependency graph from a list of groups.

  Creates nodes for each group and step, with edges representing
  `depends_on` relationships at both the group and step level.

  ## Examples

      groups = [
        %Pipette.Group{name: :lint, steps: []},
        %Pipette.Group{name: :test, depends_on: :lint, steps: []}
      ]

      graph = Pipette.Graph.from_groups(groups)
      Pipette.Graph.has_edge?(graph, :test, :lint)  #=> true
  """
  @spec from_groups([Pipette.Group.t()]) :: t()
  def from_groups(groups) do
    Enum.reduce(groups, new(), fn group, graph ->
      graph = add_node(graph, group.name)
      graph = add_group_deps(graph, group)

      Enum.reduce(group.steps, graph, fn step, g ->
        step_id = {group.name, step.name}
        g = add_node(g, step_id)
        add_step_deps(g, step, group)
      end)
    end)
  end

  defp add_group_deps(graph, %{depends_on: nil}), do: graph

  defp add_group_deps(graph, %{name: name, depends_on: dep}) when is_atom(dep) do
    add_edge(graph, name, dep)
  end

  defp add_group_deps(graph, %{name: name, depends_on: dep}) when is_binary(dep) do
    add_edge(graph, name, String.to_atom(dep))
  end

  defp add_group_deps(graph, %{name: name, depends_on: deps}) when is_list(deps) do
    Enum.reduce(deps, graph, fn
      dep, g when is_atom(dep) -> add_edge(g, name, dep)
      dep, g when is_binary(dep) -> add_edge(g, name, String.to_atom(dep))
    end)
  end

  defp add_step_deps(graph, %{depends_on: nil}, _group), do: graph

  defp add_step_deps(graph, %{name: step_name, depends_on: dep}, group) when is_atom(dep) do
    add_edge(graph, {group.name, step_name}, {group.name, dep})
  end

  defp add_step_deps(graph, %{name: step_name, depends_on: {target_group, target_step}}, group) do
    add_edge(graph, {group.name, step_name}, {target_group, target_step})
  end

  defp add_step_deps(graph, %{name: step_name, depends_on: deps}, group) when is_list(deps) do
    Enum.reduce(deps, graph, fn dep, g ->
      add_step_deps(g, %Pipette.Step{name: step_name, depends_on: dep}, group)
    end)
  end

  # String depends_on (already resolved keys) — parse back to tuple
  defp add_step_deps(graph, %{name: step_name, depends_on: dep}, group) when is_binary(dep) do
    add_edge(graph, {group.name, step_name}, parse_step_key(dep, group.name))
  end

  defp parse_step_key(key, default_group) when is_binary(key) do
    case String.split(key, "-", parts: 2) do
      [group, step] -> {String.to_atom(group), String.to_atom(step)}
      _ -> {default_group, String.to_atom(key)}
    end
  end

  @doc "Return `true` if the graph has no cycles."
  @spec acyclic?(t()) :: boolean()
  def acyclic?(%__MODULE__{} = graph) do
    find_cycle(graph) == nil
  end

  @doc """
  Find a cycle in the graph, if one exists.

  Returns a list of nodes forming the cycle path, or `nil` if the graph
  is acyclic. Uses DFS with three-color marking.
  """
  @spec find_cycle(t()) :: [node_id()] | nil
  def find_cycle(%__MODULE__{} = graph) do
    state = %{colors: %{}, path: [], cycle: nil}

    result =
      Enum.reduce_while(graph.nodes, state, fn node, state ->
        if Map.get(state.colors, node) == :black do
          {:cont, state}
        else
          case dfs_visit(graph, node, state) do
            %{cycle: nil} = state -> {:cont, state}
            %{cycle: _cycle} = state -> {:halt, state}
          end
        end
      end)

    result.cycle
  end

  defp dfs_visit(graph, node, state) do
    case Map.get(state.colors, node) do
      :gray ->
        cycle_start = Enum.find_index(state.path, &(&1 == node))
        cycle = Enum.slice(state.path, cycle_start..-1//1) ++ [node]
        %{state | cycle: cycle}

      :black ->
        state

      _ ->
        state = %{state | colors: Map.put(state.colors, node, :gray), path: state.path ++ [node]}

        neighbors = Map.get(graph.edges, node, MapSet.new())

        state =
          Enum.reduce_while(neighbors, state, fn neighbor, state ->
            case dfs_visit(graph, neighbor, state) do
              %{cycle: nil} = state -> {:cont, state}
              state -> {:halt, state}
            end
          end)

        case state.cycle do
          nil ->
            %{
              state
              | colors: Map.put(state.colors, node, :black),
                path: List.delete(state.path, node)
            }

          _ ->
            state
        end
    end
  end

  @doc """
  Compute the transitive dependencies (ancestors) of a node.

  Follows edges recursively to find all nodes that `node` depends on,
  directly or transitively.

  ## Examples

      graph = Pipette.Graph.from_groups([
        %Pipette.Group{name: :lint, steps: []},
        %Pipette.Group{name: :test, depends_on: :lint, steps: []},
        %Pipette.Group{name: :deploy, depends_on: :test, steps: []}
      ])

      Pipette.Graph.ancestors(graph, :deploy)
      #=> MapSet.new([:test, :lint])
  """
  @spec ancestors(t(), node_id()) :: MapSet.t(node_id())
  def ancestors(%__MODULE__{} = graph, node) do
    do_ancestors(graph, node, MapSet.new())
  end

  defp do_ancestors(graph, node, visited) do
    deps = Map.get(graph.edges, node, MapSet.new())

    Enum.reduce(deps, visited, fn dep, visited ->
      if MapSet.member?(visited, dep) do
        visited
      else
        visited = MapSet.put(visited, dep)
        do_ancestors(graph, dep, visited)
      end
    end)
  end
end
