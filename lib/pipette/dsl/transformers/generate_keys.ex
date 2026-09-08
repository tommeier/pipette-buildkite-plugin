defmodule Pipette.Dsl.Transformers.GenerateKeys do
  @moduledoc """
  Compile-time transformer that derives Buildkite key strings for
  groups, steps, and triggers.

  - Group key: `Atom.to_string(group.name)` (e.g. `:api` -> `"api"`)
  - Step key: `"\#{group_key}-\#{step.name}"` (e.g. `"api-test"`)
  - Top-level trigger key: `Atom.to_string(trigger.name)`
    (e.g. `:deploy` -> `"deploy"`)
  - Nested trigger key (inside a group): same scheme as a step,
    `"\#{group_key}-\#{trigger.name}"` (e.g. `"deploy-rollout"`)

  Also resolves step `depends_on` atoms to sibling step keys and
  `{group, step}` tuples to the target step's key — its explicit `key:`
  when it has one, otherwise the derived form. A tuple whose target is
  not defined in the pipeline (a group supplied at runtime) falls back
  to the derived `"group-step"`. Trigger `depends_on` (top-level or
  nested) stays as atoms and is resolved at runtime by `Pipette.run/2`
  against the group key map.
  """

  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    entities = Spark.Dsl.Transformer.get_entities(dsl_state, [:pipeline])

    groups = Enum.filter(entities, &is_struct(&1, Pipette.Group))
    triggers = Enum.filter(entities, &is_struct(&1, Pipette.Trigger))

    # {group_name, child_name} -> key for every step and nested trigger, so a
    # cross-group `{group, step}` ref resolves to the target's actual key
    # whatever order the groups are defined in.
    global_key_map =
      Map.new(
        for group <- groups, child <- group.steps do
          {{group.name, child.name}, child_key(group, child)}
        end
      )

    dsl_state =
      Enum.reduce(groups, dsl_state, fn group, dsl ->
        group_key = group_key(group)

        # First pass: assign keys to all steps and nested triggers.
        # Both Pipette.Step and Pipette.Trigger have `:key` and `:name`
        # fields, so the same struct-update works for both.
        keyed_steps =
          Enum.map(group.steps, fn child -> %{child | key: child_key(group, child)} end)

        # Build lookup of name -> actual key for dependency resolution.
        # Includes both steps and nested triggers — a step can depend on
        # a sibling trigger's key by name, and vice versa.
        step_key_map = Map.new(keyed_steps, fn child -> {child.name, child.key} end)

        # Second pass: resolve depends_on.
        #
        # Steps: atom deps resolve against sibling step_key_map; if not
        # found, fall back to "{group_key}-{atom}" (existing behavior).
        # Tuple deps resolve against global_key_map.
        #
        # Nested triggers: atom deps resolve against sibling step_key_map
        # first; if not found, the atom is left for runtime resolution
        # against the top-level group key map (mirroring top-level
        # trigger semantics). String deps pass through unchanged.
        steps =
          Enum.map(keyed_steps, fn
            %Pipette.Step{} = step ->
              resolved_deps =
                resolve_step_depends_on(step.depends_on, group_key, step_key_map, global_key_map)

              %{step | depends_on: resolved_deps}

            %Pipette.Trigger{} = trigger ->
              resolved_deps =
                resolve_nested_trigger_depends_on(
                  trigger.depends_on,
                  step_key_map,
                  global_key_map
                )

              %{trigger | depends_on: resolved_deps}
          end)

        # Flatten nested scope ref into top-level group fields for the activation engine.
        {scope, ignore_global_scope} =
          case group.scope_refs do
            [%Pipette.ScopeRef{name: name, ignore_global: ig}] -> {name, ig}
            _ -> {group.scope, group.ignore_global_scope}
          end

        # Group depends_on stays as atoms — the activation engine needs atom names.
        # The Buildkite serializer resolves to key strings at YAML output time.
        updated = %{
          group
          | key: group_key,
            steps: steps,
            scope: scope,
            ignore_global_scope: ignore_global_scope
        }

        Spark.Dsl.Transformer.replace_entity(dsl, [:pipeline], updated)
      end)

    dsl_state =
      Enum.reduce(triggers, dsl_state, fn trigger, dsl ->
        trigger_key = trigger.key || Atom.to_string(trigger.name)
        # Trigger depends_on stays as atoms — same reason as groups.
        updated = %{trigger | key: trigger_key}
        Spark.Dsl.Transformer.replace_entity(dsl, [:pipeline], updated)
      end)

    {:ok, dsl_state}
  end

  defp group_key(group), do: group.key || Atom.to_string(group.name)
  defp child_key(group, child), do: child.key || "#{group_key(group)}-#{child.name}"

  defp resolve_step_depends_on(nil, _group_key, _map, _global), do: nil
  defp resolve_step_depends_on(dep, _group_key, _map, _global) when is_binary(dep), do: dep

  defp resolve_step_depends_on(%Pipette.Optional{dep: dep}, group_key, map, global),
    do: %Pipette.Optional{dep: resolve_step_depends_on(dep, group_key, map, global)}

  defp resolve_step_depends_on(dep, group_key, step_key_map, _global) when is_atom(dep) do
    # Look up the actual key of the referenced step within the same group.
    # Falls back to "group_key-step_name" if the step isn't found (cross-group ref).
    Map.get(step_key_map, dep, "#{group_key}-#{dep}")
  end

  defp resolve_step_depends_on({target_group, target_step} = ref, _group_key, _map, global)
       when is_atom(target_group) and is_atom(target_step),
       do: Map.get(global, ref, "#{target_group}-#{target_step}")

  defp resolve_step_depends_on(deps, group_key, step_key_map, global) when is_list(deps),
    do: Enum.map(deps, &resolve_step_depends_on(&1, group_key, step_key_map, global))

  # Resolution for a nested trigger's depends_on. Sibling-step atoms are
  # resolved at compile time. Atoms with no sibling match are left for
  # the runtime resolver in `Pipette.run/2` (which maps them against the
  # top-level group key map). Strings always pass through.
  defp resolve_nested_trigger_depends_on(nil, _map, _global), do: nil
  defp resolve_nested_trigger_depends_on(dep, _map, _global) when is_binary(dep), do: dep

  defp resolve_nested_trigger_depends_on(%Pipette.Optional{dep: dep}, map, global),
    do: %Pipette.Optional{dep: resolve_nested_trigger_depends_on(dep, map, global)}

  defp resolve_nested_trigger_depends_on(dep, map, _global) when is_atom(dep) do
    case Map.get(map, dep) do
      nil -> dep
      key -> key
    end
  end

  # A cross-group tuple resolves here when its target is defined; otherwise the
  # tuple is left for the runtime resolver.
  defp resolve_nested_trigger_depends_on({target_group, target_step} = ref, _map, global)
       when is_atom(target_group) and is_atom(target_step),
       do: Map.get(global, ref, ref)

  defp resolve_nested_trigger_depends_on(deps, map, global) when is_list(deps),
    do: Enum.map(deps, &resolve_nested_trigger_depends_on(&1, map, global))
end
