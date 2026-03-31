defmodule Pipette.Dsl.Transformers.GenerateKeys do
  @moduledoc """
  Compile-time transformer that derives Buildkite key strings for
  groups, steps, and triggers.

  - Group key: `Atom.to_string(group.name)` (e.g. `:api` -> `"api"`)
  - Step key: `"\#{group_key}-\#{step.name}"` (e.g. `"api-test"`)
  - Trigger key: `Atom.to_string(trigger.name)` (e.g. `:deploy` -> `"deploy"`)

  Also resolves `depends_on` atoms/tuples to their key strings.
  """

  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    entities = Spark.Dsl.Transformer.get_entities(dsl_state, [:pipeline])

    groups = Enum.filter(entities, &is_struct(&1, Pipette.Group))
    triggers = Enum.filter(entities, &is_struct(&1, Pipette.Trigger))

    dsl_state =
      Enum.reduce(groups, dsl_state, fn group, dsl ->
        group_key = group.key || Atom.to_string(group.name)

        steps =
          Enum.map(group.steps, fn step ->
            step_key = step.key || "#{group_key}-#{step.name}"
            resolved_deps = resolve_step_depends_on(step.depends_on, group_key)
            %{step | key: step_key, depends_on: resolved_deps}
          end)

        resolved_deps = resolve_group_depends_on(group.depends_on)
        updated = %{group | key: group_key, steps: steps, depends_on: resolved_deps}
        Spark.Dsl.Transformer.replace_entity(dsl, [:pipeline], updated)
      end)

    dsl_state =
      Enum.reduce(triggers, dsl_state, fn trigger, dsl ->
        trigger_key = trigger.key || Atom.to_string(trigger.name)
        resolved_deps = resolve_group_depends_on(trigger.depends_on)
        updated = %{trigger | key: trigger_key, depends_on: resolved_deps}
        Spark.Dsl.Transformer.replace_entity(dsl, [:pipeline], updated)
      end)

    {:ok, dsl_state}
  end

  defp resolve_group_depends_on(nil), do: nil
  defp resolve_group_depends_on(dep) when is_atom(dep), do: Atom.to_string(dep)

  defp resolve_group_depends_on(deps) when is_list(deps),
    do: Enum.map(deps, &resolve_group_depends_on/1)

  defp resolve_step_depends_on(nil, _group_key), do: nil
  defp resolve_step_depends_on(dep, _group_key) when is_binary(dep), do: dep

  defp resolve_step_depends_on(dep, group_key) when is_atom(dep),
    do: "#{group_key}-#{dep}"

  defp resolve_step_depends_on({target_group, target_step}, _group_key)
       when is_atom(target_group) and is_atom(target_step),
       do: "#{target_group}-#{target_step}"

  defp resolve_step_depends_on(deps, group_key) when is_list(deps),
    do: Enum.map(deps, &resolve_step_depends_on(&1, group_key))
end
