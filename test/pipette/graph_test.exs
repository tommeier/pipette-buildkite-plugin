defmodule Pipette.GraphTest do
  use ExUnit.Case, async: true

  alias Pipette.Graph

  describe "from_groups/1" do
    test "builds graph from groups with no dependencies" do
      groups = [
        %Pipette.Group{name: :backend, steps: []},
        %Pipette.Group{name: :native, steps: []}
      ]

      graph = Graph.from_groups(groups)

      assert Graph.has_node?(graph, :backend)
      assert Graph.has_node?(graph, :native)
      assert Graph.edges(graph) == []
    end

    test "builds graph with group-to-group dependencies" do
      groups = [
        %Pipette.Group{name: :backend, steps: []},
        %Pipette.Group{name: :packaging, depends_on: :backend, steps: []}
      ]

      graph = Graph.from_groups(groups)

      assert Graph.has_edge?(graph, :packaging, :backend)
    end

    test "builds graph with list dependencies" do
      groups = [
        %Pipette.Group{name: :backend, steps: []},
        %Pipette.Group{name: :native, steps: []},
        %Pipette.Group{name: :deploy, depends_on: [:backend, :native], steps: []}
      ]

      graph = Graph.from_groups(groups)

      assert Graph.has_edge?(graph, :deploy, :backend)
      assert Graph.has_edge?(graph, :deploy, :native)
    end

    test "builds graph with step-level dependencies" do
      groups = [
        %Pipette.Group{
          name: :deploy,
          steps: [
            %Pipette.Step{name: :pre_release},
            %Pipette.Step{name: :ios, depends_on: :pre_release},
            %Pipette.Step{name: :android, depends_on: :pre_release},
            %Pipette.Step{name: :post, depends_on: [:ios, :android]}
          ]
        }
      ]

      graph = Graph.from_groups(groups)

      assert Graph.has_node?(graph, {:deploy, :pre_release})
      assert Graph.has_node?(graph, {:deploy, :ios})
      assert Graph.has_edge?(graph, {:deploy, :ios}, {:deploy, :pre_release})
      assert Graph.has_edge?(graph, {:deploy, :android}, {:deploy, :pre_release})
      assert Graph.has_edge?(graph, {:deploy, :post}, {:deploy, :ios})
      assert Graph.has_edge?(graph, {:deploy, :post}, {:deploy, :android})
    end
  end

  describe "acyclic?/1" do
    test "returns true for a DAG" do
      groups = [
        %Pipette.Group{name: :backend, steps: []},
        %Pipette.Group{name: :packaging, depends_on: :backend, steps: []},
        %Pipette.Group{name: :deploy, depends_on: :packaging, steps: []}
      ]

      graph = Graph.from_groups(groups)
      assert Graph.acyclic?(graph) == true
    end

    test "returns false for a graph with a cycle" do
      graph =
        Graph.new()
        |> Graph.add_node(:a)
        |> Graph.add_node(:b)
        |> Graph.add_node(:c)
        |> Graph.add_edge(:a, :b)
        |> Graph.add_edge(:b, :c)
        |> Graph.add_edge(:c, :a)

      assert Graph.acyclic?(graph) == false
    end

    test "returns true for an empty graph" do
      graph = Graph.new()
      assert Graph.acyclic?(graph) == true
    end

    test "returns true for isolated nodes" do
      graph =
        Graph.new()
        |> Graph.add_node(:a)
        |> Graph.add_node(:b)

      assert Graph.acyclic?(graph) == true
    end
  end

  describe "find_cycle/1" do
    test "returns nil for a DAG" do
      groups = [
        %Pipette.Group{name: :backend, steps: []},
        %Pipette.Group{name: :packaging, depends_on: :backend, steps: []}
      ]

      graph = Graph.from_groups(groups)
      assert Graph.find_cycle(graph) == nil
    end

    test "returns the cycle path for a cyclic graph" do
      graph =
        Graph.new()
        |> Graph.add_node(:a)
        |> Graph.add_node(:b)
        |> Graph.add_node(:c)
        |> Graph.add_edge(:a, :b)
        |> Graph.add_edge(:b, :c)
        |> Graph.add_edge(:c, :a)

      cycle = Graph.find_cycle(graph)
      assert is_list(cycle)
      assert length(cycle) > 0
      # The cycle should contain all three nodes
      assert :a in cycle
      assert :b in cycle
      assert :c in cycle
    end
  end

  describe "ancestors/2" do
    test "returns transitive dependencies" do
      groups = [
        %Pipette.Group{name: :backend, steps: []},
        %Pipette.Group{name: :packaging, depends_on: :backend, steps: []},
        %Pipette.Group{name: :deploy, depends_on: :packaging, steps: []}
      ]

      graph = Graph.from_groups(groups)
      ancestors = Graph.ancestors(graph, :deploy)

      assert :packaging in ancestors
      assert :backend in ancestors
    end

    test "returns empty set for node with no dependencies" do
      groups = [
        %Pipette.Group{name: :backend, steps: []}
      ]

      graph = Graph.from_groups(groups)
      assert Graph.ancestors(graph, :backend) == MapSet.new()
    end
  end
end
