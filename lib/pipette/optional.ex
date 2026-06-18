defmodule Pipette.Optional do
  @moduledoc """
  Marks a `depends_on` reference as optional.

  A normal dependency on a group or step that this build didn't activate
  dangles — Buildkite rejects the upload because the key doesn't exist. That
  is the right default: a missing required dependency should fail loudly.

  Some dependencies are legitimately conditional, though. In a change-scoped
  pipeline a group only renders when its files change, so a trigger that wants
  to wait for it *when it runs* can't require it. Wrapping the reference in
  `optional/1` (see `Pipette.Constructors`) tells `Pipette.run/2` to drop it
  when its target is defined in the pipeline but not active in this build:

      import Pipette.Constructors, only: [optional: 1]

      trigger :deploy_downstream do
        pipeline "production-deploy"
        depends_on [:api, optional(:web)]
      end

  An optional reference to a target that exists *nowhere* (a typo or a stale
  rename) is still kept and still fails the upload — only a defined-but-inactive
  target is dropped.
  """

  @enforce_keys [:dep]
  defstruct [:dep]

  @type ref :: atom() | {atom(), atom()} | String.t()
  @type t :: %__MODULE__{dep: ref()}
end
