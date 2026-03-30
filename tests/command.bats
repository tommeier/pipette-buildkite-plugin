#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR

  # Clean plugin config vars
  unset BUILDKITE_PLUGIN_PIPETTE_PIPELINE

  # Set up mock bin directory (prepend to PATH)
  mkdir -p "${TEST_TMPDIR}/mock-bin"
  export PATH="${TEST_TMPDIR}/mock-bin:${PATH}"

  write_mock_elixir
}

write_mock_elixir() {
  cat > "${TEST_TMPDIR}/mock-bin/elixir" <<'MOCK'
#!/usr/bin/env bash
echo "pipeline executed: $1"
MOCK
  chmod +x "${TEST_TMPDIR}/mock-bin/elixir"
}

teardown() {
  rm -rf "${TEST_TMPDIR}"
}

# ── Happy path ───────────────────────────────────────────────

@test "Uses default pipeline path when env var not set" {
  run bash hooks/command

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"pipeline executed: .buildkite/pipeline.exs"* ]]
}

@test "Uses custom pipeline path from env var" {
  export BUILDKITE_PLUGIN_PIPETTE_PIPELINE="custom/path.exs"

  run bash hooks/command

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"pipeline executed: custom/path.exs"* ]]
}

@test "Prints header with pipeline path" {
  run bash hooks/command

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Generating pipeline from .buildkite/pipeline.exs"* ]]
}

# ── Error handling ───────────────────────────────────────────

@test "Fails when elixir is not installed" {
  rm "${TEST_TMPDIR}/mock-bin/elixir"

  run bash hooks/command

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Elixir is not installed"* ]]
}

@test "Fails when elixir script exits non-zero" {
  cat > "${TEST_TMPDIR}/mock-bin/elixir" <<'MOCK'
#!/usr/bin/env bash
echo "compile error" >&2
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/mock-bin/elixir"

  run bash hooks/command

  [ "${status}" -ne 0 ]
}
