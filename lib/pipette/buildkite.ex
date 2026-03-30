defmodule Pipette.Buildkite do
  @moduledoc """
  Serializes pipeline groups/steps to Buildkite YAML format.

  Converts `Pipette.Group`, `Pipette.Step`, and `Pipette.Trigger` structs
  into a Buildkite pipeline YAML document using `Ymlr`.

  ## Usage

      groups = [
        %Pipette.Group{
          name: :backend,
          label: ":elixir: Backend",
          key: "backend",
          steps: [
            %Pipette.Step{
              name: :test,
              label: ":test_tube: Test",
              command: "mix test",
              key: "backend-test"
            }
          ]
        }
      ]

      Pipette.Buildkite.to_yaml(groups)

  Produces:

      ---
      steps:
      - group: ':elixir: Backend'
        key: backend
        steps:
        - label: ':test_tube: Test'
          key: backend-test
          command: mix test

  Pipeline-level configuration and triggers can be passed as additional
  arguments:

      Pipette.Buildkite.to_yaml(groups, %{env: %{LANG: "C.UTF-8"}}, triggers)
  """

  @doc """
  Serialize groups, pipeline config, and triggers to a Buildkite YAML document.

  Returns a YAML string starting with `---` that can be piped to
  `buildkite-agent pipeline upload`.

  ## Examples

      groups = [%Pipette.Group{name: :api, label: ":elixir: API", key: "api", steps: [...]}]
      yaml = Pipette.Buildkite.to_yaml(groups)

      yaml = Pipette.Buildkite.to_yaml(groups, %{env: %{MIX_ENV: "test"}}, triggers)
  """
  @spec to_yaml([Pipette.Group.t()], map(), [Pipette.Trigger.t()]) :: String.t()
  def to_yaml(groups, pipeline_config \\ %{}, triggers \\ []) do
    group_steps = Enum.map(groups, &serialize_group/1)
    trigger_steps = Enum.map(triggers, &serialize_trigger/1)

    pipeline =
      pipeline_config
      |> serialize_pipeline_config()
      |> Map.put("steps", group_steps ++ trigger_steps)

    Ymlr.document!(pipeline)
  end

  defp serialize_pipeline_config(config) do
    %{}
    |> put_if("env", maybe_stringify_keys(config[:env]))
    |> put_if("secrets", config[:secrets])
    |> put_if("cache", config[:cache] && stringify_keys(Map.new(config[:cache])))
  end

  defp serialize_group(group) do
    %{
      "group" => group.label || to_string(group.name),
      "key" => group.key || to_string(group.name),
      "steps" => Enum.map(group.steps, &serialize_step/1)
    }
    |> put_if("depends_on", serialize_depends_on(group.depends_on))
  end

  defp serialize_step(step) do
    %{
      "label" => step.label,
      "key" => step.key || to_string(step.name)
    }
    |> put_if("command", step.command)
    |> put_if("depends_on", serialize_depends_on(step.depends_on))
    |> put_if("env", maybe_stringify_keys(step.env))
    |> put_if("agents", maybe_stringify_keys(step.agents))
    |> put_if("plugins", serialize_plugins(step.plugins))
    |> put_if("secrets", step.secrets)
    |> put_if("timeout_in_minutes", step.timeout_in_minutes)
    |> put_if("concurrency", step.concurrency)
    |> put_if("concurrency_group", step.concurrency_group)
    |> put_if("concurrency_method", step.concurrency_method)
    |> put_if("soft_fail", step.soft_fail)
    |> put_if("retry", serialize_retry(step.retry))
    |> put_if("artifact_paths", step.artifact_paths)
    |> put_if("parallelism", step.parallelism)
    |> put_if("priority", step.priority)
    |> put_if("skip", step.skip)
    |> put_if("cancel_on_build_failing", step.cancel_on_build_failing)
    |> put_if("allow_dependency_failure", step.allow_dependency_failure)
    |> put_if("branches", step.branches)
    |> put_if("if", step.if_condition)
    |> put_if("matrix", step.matrix)
  end

  defp serialize_trigger(trigger) do
    %{
      "trigger" => trigger.pipeline,
      "label" => trigger.label || to_string(trigger.name)
    }
    |> put_if("key", trigger.key)
    |> put_if("depends_on", serialize_depends_on(trigger.depends_on))
    |> put_if("async", trigger.async)
    |> put_if("build", maybe_stringify_keys(trigger.build))
  end

  defp serialize_depends_on(nil), do: nil
  defp serialize_depends_on(dep) when is_binary(dep), do: dep
  defp serialize_depends_on(dep) when is_atom(dep), do: to_string(dep)
  defp serialize_depends_on(deps) when is_list(deps), do: Enum.map(deps, &serialize_depends_on/1)

  defp serialize_plugins(nil), do: nil
  defp serialize_plugins([]), do: nil

  defp serialize_plugins(plugins) do
    Enum.map(plugins, fn
      {name, nil} -> %{name => nil}
      {name, opts} when is_map(opts) -> %{name => stringify_keys(opts)}
      {name, opts} when is_list(opts) -> %{name => stringify_keys(Map.new(opts))}
      other -> other
    end)
  end

  defp serialize_retry(nil), do: nil
  defp serialize_retry(retry) when is_map(retry), do: stringify_keys_deep(retry)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys_deep(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value_deep(v)} end)
  end

  defp stringify_value_deep(list) when is_list(list), do: Enum.map(list, &stringify_value_deep/1)
  defp stringify_value_deep(map) when is_map(map), do: stringify_keys_deep(map)
  defp stringify_value_deep(other), do: other

  defp maybe_stringify_keys(nil), do: nil
  defp maybe_stringify_keys(map) when is_map(map), do: stringify_keys(map)

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
