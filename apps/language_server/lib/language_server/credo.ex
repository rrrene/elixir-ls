defmodule ElixirLS.LanguageServer.Credo do
  alias ElixirLS.LanguageServer.{JsonRpc, Server}
  use GenServer

  defstruct [
    :parent,
    :root_path,
    :build_ref,
    :warn_opts
  ]

  # Client API

  def start_link({parent, root_path}) do
    GenServer.start_link(__MODULE__, {parent, root_path}, name: {:global, {parent, __MODULE__}})
  end

  def analyze(parent \\ self(), build_ref, warn_opts) do
    GenServer.cast(
      {:global, {parent, __MODULE__}},
      {:analyze, build_ref, warn_opts}
    )
  end

  def analysis_finished(server, status, warnings, timestamp, build_ref) do
    GenServer.call(
      server,
      {
        :analysis_finished,
        status,
        warnings,
        timestamp,
        build_ref
      },
      :infinity
    )
  end

  # Server callbacks

  @impl GenServer
  def init({parent, root_path}) do
    state = %__MODULE__{parent: parent, root_path: root_path}

    {:ok, state}
  end

  @impl GenServer
  def handle_call(
        {
          :analysis_finished,
          status,
          warnings,
          _timestamp,
          build_ref
        },
        _from,
        state
      ) do
    diagnostics = to_diagnostics(warnings)

    Server.credo_finished(state.parent, status, diagnostics, build_ref)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:analyze, build_ref, warn_opts}, state) do
    state =
      ElixirLS.LanguageServer.Build.with_build_lock(fn ->
        if Mix.Project.get() do
          JsonRpc.log_message(:info, "[ElixirLS Credo] Checking ...")

          state = %{
            state
            | warn_opts: warn_opts,
              build_ref: build_ref
          }

          trigger_analyze(state)
        else
          state
        end
      end)

    {:noreply, state}
  end

  defp trigger_analyze(state) do
    parent = self()

    _analysis_pid = spawn_link(fn -> run_credo(parent, state) end)

    state
  end

  defp run_credo(parent, state) do
    %{
      root_path: _root_path,
      build_ref: build_ref
    } = state

    # TODO: what is `timestamp`  good for?
    timestamp = nil

    {us, {status, warnings}} =
      :timer.tc(fn ->
        JsonRpc.log_message(
          :info,
          "[ElixirLS Credo] Analyzing ..."
        )

        warnings = []

        {:ok, warnings}
      end)

    JsonRpc.log_message(
      :info,
      "[ElixirLS Credo] Analysis finished in #{div(us, 1000)} milliseconds"
    )

    analysis_finished(parent, status, warnings, timestamp, build_ref)
  end

  defp to_diagnostics(warnings_map) do
    warnings_map
  end

  # defp to_diagnostics(warnings_map, warn_opts) do
  #   tags_enabled = Analyzer.matching_tags(warn_opts)

  #   for {_beam_file, warnings} <- warnings_map,
  #       {source_file, line, data} <- warnings,
  #       {tag, _, _} = data,
  #       tag in tags_enabled,
  #       source_file = Path.absname(to_string(source_file)),
  #       in_project?(source_file),
  #       not String.starts_with?(source_file, Mix.Project.deps_path()) do
  #     %Mix.Task.Compiler.Diagnostic{
  #       compiler_name: "ElixirLS Dialyzer",
  #       file: source_file,
  #       position: line,
  #       message: warning_message(data, warning_format),
  #       severity: :warning,
  #       details: data
  #     }
  #   end
  # end
end
