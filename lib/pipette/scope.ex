defmodule Pipette.Scope do
  @moduledoc """
  File-affinity scope for activation.

  Maps a named scope to file glob patterns. When any file matching
  `:files` (and not matching `:exclude`) is changed, the scope is
  considered active and its associated groups run.

  ## Fields

    * `:name` (`atom()`) — unique identifier for this scope
      (e.g. `:api_code`, `:web_code`)
    * `:files` (`[String.t()]`) — glob patterns that trigger this scope
      (e.g. `["apps/api/**", "libs/shared/**"]`)
    * `:exclude` (`[String.t()] | nil`) — glob patterns to exclude from
      matching (e.g. `["apps/api/docs/**"]`)
    * `:activates` (`:all | nil`) — when set to `:all`, a match on this
      scope activates every group in the pipeline regardless of their
      own scope bindings

  ## Example

      %Pipette.Scope{
        name: :api_code,
        files: ["apps/api/**"],
        exclude: ["apps/api/docs/**"],
        activates: nil
      }

      %Pipette.Scope{
        name: :infra,
        files: ["infra/**", "terraform/**"],
        activates: :all
      }
  """

  defstruct [:name, :files, :exclude, :activates, :__spark_metadata__]

  @type t :: %__MODULE__{
          name: atom(),
          files: [String.t()],
          exclude: [String.t()] | nil,
          activates: :all | nil
        }
end
