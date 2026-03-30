defmodule Pipette.Activation do
  @moduledoc """
  The activation engine -- determines which groups and steps should run.

  Combines branch policies, scope-based change detection, commit message
  targeting, dependency propagation, and `only` branch filtering into
  a single resolution pipeline.
  """

  alias Pipette.{Context, Git, Target}

  @type result :: %{groups: [Pipette.Group.t()]}

  @spec resolve(Pipette.Pipeline.t(), Context.t(), [String.t()] | :all, MapSet.t(atom()) | :all) ::
          result()
  def resolve(
        %Pipette.Pipeline{} = pipeline,
        %Context{} = ctx,
        changed_files,
        force_groups \\ MapSet.new()
      ) do
    policy = match_branch_policy(pipeline.branches, ctx.branch)

    {active_groups, targets} =
      if changed_files == :all do
        {pipeline.groups, nil}
      else
        determine_active_groups(
          policy,
          ctx,
          pipeline.scopes,
          pipeline.groups,
          changed_files,
          pipeline.ignore
        )
      end

    active_groups =
      case force_groups do
        :all ->
          pipeline.groups

        force_set when is_struct(force_set, MapSet) ->
          if MapSet.size(force_set) > 0 do
            existing = MapSet.new(active_groups, & &1.name)

            forced =
              Enum.filter(pipeline.groups, &(&1.name in force_set and &1.name not in existing))

            active_groups ++ forced
          else
            active_groups
          end
      end

    active_groups = pull_dependencies(active_groups, pipeline.groups)
    active_groups = apply_only_filter(active_groups, ctx, force_groups)
    active_groups = apply_step_filter(active_groups, targets)

    %{groups: active_groups}
  end

  defp match_branch_policy(branches, current_branch) do
    Enum.find(branches, fn branch ->
      Git.matches_glob?(current_branch, branch.pattern)
    end)
  end

  defp determine_active_groups(policy, ctx, scopes, groups, changed_files, ignore) do
    cond do
      policy != nil and policy.scopes == :all ->
        {groups, nil}

      policy != nil and is_list(policy.scopes) ->
        fired = MapSet.new(policy.scopes)
        {activate_from_scopes(fired, scopes, groups), nil}

      true ->
        targeting_disabled = policy != nil and :targeting in (policy.disable || [])

        case resolve_targets(ctx, targeting_disabled) do
          {:ok, targets} ->
            {activate_from_targets(targets, groups), targets}

          :none ->
            {activate_from_changes(scopes, groups, changed_files, ignore), nil}
        end
    end
  end

  defp resolve_targets(_ctx, true = _disabled), do: :none

  defp resolve_targets(ctx, false) do
    Target.resolve(ctx)
  end

  defp activate_from_scopes(fired, scopes, groups) do
    if Enum.any?(scopes, &(&1.name in fired and &1.activates == :all)) do
      groups
    else
      directly_active =
        groups
        |> Enum.filter(fn group ->
          group.scope != nil and is_atom(group.scope) and MapSet.member?(fired, group.scope)
        end)
        |> MapSet.new(& &1.name)

      propagated = propagate_dependencies(directly_active, groups)
      Enum.filter(groups, &(&1.name in propagated))
    end
  end

  defp activate_from_changes(scopes, groups, changed_files, ignore) do
    if Git.all_ignored?(changed_files, ignore) do
      []
    else
      fired = Git.fired_scopes(scopes, changed_files)
      activate_from_scopes(fired, scopes, groups)
    end
  end

  defp activate_from_targets(targets, groups) do
    graph = Pipette.Graph.from_groups(groups)

    active =
      Enum.reduce(targets.groups, MapSet.new(), fn group_name, acc ->
        ancestors = Pipette.Graph.ancestors(graph, group_name)
        acc |> MapSet.put(group_name) |> MapSet.union(ancestors)
      end)

    Enum.filter(groups, &(&1.name in active))
  end

  defp propagate_dependencies(active_names, groups) do
    do_propagate(active_names, groups)
  end

  defp do_propagate(active, groups) do
    new_active =
      Enum.reduce(groups, active, fn group, acc ->
        if group.name in acc do
          acc
        else
          if group.scope == nil and depends_on_active?(group, acc) do
            MapSet.put(acc, group.name)
          else
            acc
          end
        end
      end)

    if MapSet.size(new_active) == MapSet.size(active) do
      active
    else
      do_propagate(new_active, groups)
    end
  end

  defp depends_on_active?(%{depends_on: nil}, _active), do: false

  defp depends_on_active?(%{depends_on: dep}, active) when is_atom(dep) do
    dep in active
  end

  defp depends_on_active?(%{depends_on: dep}, active) when is_binary(dep) do
    String.to_existing_atom(dep) in active
  end

  defp depends_on_active?(%{depends_on: deps}, active) when is_list(deps) do
    Enum.any?(deps, fn
      dep when is_atom(dep) -> dep in active
      dep when is_binary(dep) -> String.to_existing_atom(dep) in active
    end)
  end

  defp pull_dependencies(active_groups, all_groups) do
    active_names = MapSet.new(active_groups, & &1.name)
    required = pull_deps_recursive(active_names, all_groups)

    if MapSet.size(required) == MapSet.size(active_names) do
      active_groups
    else
      new_groups =
        all_groups
        |> Enum.filter(&(&1.name in required and &1.name not in active_names))

      active_groups ++ new_groups
    end
  end

  defp pull_deps_recursive(active, groups) do
    new_active =
      Enum.reduce(groups, active, fn group, acc ->
        if group.name in acc do
          deps = normalize_deps(group.depends_on)
          Enum.reduce(deps, acc, &MapSet.put(&2, &1))
        else
          acc
        end
      end)

    if MapSet.size(new_active) == MapSet.size(active) do
      active
    else
      pull_deps_recursive(new_active, groups)
    end
  end

  defp normalize_deps(nil), do: []
  defp normalize_deps(dep) when is_atom(dep), do: [dep]
  defp normalize_deps(dep) when is_binary(dep), do: [String.to_existing_atom(dep)]

  defp normalize_deps(deps) when is_list(deps) do
    Enum.map(deps, fn
      dep when is_atom(dep) -> dep
      dep when is_binary(dep) -> String.to_existing_atom(dep)
    end)
  end

  defp apply_only_filter(groups, %Context{} = ctx, force_groups) do
    Enum.filter(groups, fn group ->
      bypassed =
        force_groups == :all or
          (is_struct(force_groups, MapSet) and group.name in force_groups)

      if bypassed do
        true
      else
        case group.only do
          nil -> true
          only when is_binary(only) -> Git.matches_glob?(ctx.branch, only)
          only when is_list(only) -> Enum.any?(only, &Git.matches_glob?(ctx.branch, &1))
        end
      end
    end)
  end

  defp apply_step_filter(groups, nil), do: groups

  defp apply_step_filter(groups, %{steps: targeted_steps}) do
    if MapSet.size(targeted_steps) == 0 do
      groups
    else
      groups
      |> Enum.map(fn group ->
        group_step_targets =
          targeted_steps
          |> Enum.filter(fn {g, _s} -> g == group.name end)
          |> Enum.map(fn {_g, s} -> s end)
          |> MapSet.new()

        if MapSet.size(group_step_targets) == 0 do
          group
        else
          required = resolve_step_deps(group_step_targets, group.steps)
          filtered_steps = Enum.filter(group.steps, &(&1.name in required))
          %{group | steps: filtered_steps}
        end
      end)
      |> Enum.reject(fn group -> group.steps == [] end)
    end
  end

  defp resolve_step_deps(targeted, steps) do
    step_map = Map.new(steps, &{&1.name, &1})
    do_resolve_step_deps(targeted, step_map)
  end

  defp do_resolve_step_deps(required, step_map) do
    new_required =
      Enum.reduce(required, required, fn step_name, acc ->
        case Map.get(step_map, step_name) do
          nil ->
            acc

          step ->
            deps = step_depends_on_names(step.depends_on)
            Enum.reduce(deps, acc, &MapSet.put(&2, &1))
        end
      end)

    if MapSet.size(new_required) == MapSet.size(required) do
      required
    else
      do_resolve_step_deps(new_required, step_map)
    end
  end

  defp step_depends_on_names(nil), do: []
  defp step_depends_on_names(dep) when is_atom(dep), do: [dep]

  defp step_depends_on_names(dep) when is_binary(dep) do
    case String.split(dep, "-", parts: 2) do
      [_group, step] -> [String.to_existing_atom(step)]
      _ -> []
    end
  end

  defp step_depends_on_names(deps) when is_list(deps) do
    Enum.flat_map(deps, &step_depends_on_names/1)
  end
end
