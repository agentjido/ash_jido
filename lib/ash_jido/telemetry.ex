defmodule AshJido.Telemetry do
  @moduledoc false

  @start_event [:jido, :action, :ash_jido, :start]
  @stop_event [:jido, :action, :ash_jido, :stop]
  @exception_event [:jido, :action, :ash_jido, :exception]

  @type span_state :: %{metadata: map(), start_mono: integer()} | nil

  @spec start(struct(), map()) :: span_state()
  def start(%{telemetry?: true}, metadata) do
    :telemetry.execute(
      @start_event,
      %{system_time: System.system_time(:nanosecond)},
      metadata
    )

    %{
      metadata: metadata,
      start_mono: System.monotonic_time(:nanosecond)
    }
  end

  def start(_config, _metadata), do: nil

  @spec stop(span_state(), term(), map()) :: :ok
  def stop(nil, _result, _signal_meta), do: :ok

  def stop(%{metadata: metadata, start_mono: start_mono}, result, signal_meta) do
    :telemetry.execute(
      @stop_event,
      %{
        duration: System.monotonic_time(:nanosecond) - start_mono,
        system_time: System.system_time(:nanosecond)
      },
      metadata
      |> Map.put(:result_status, result_status(result))
      |> merge_signal_meta(signal_meta)
    )
  end

  @spec exception(span_state(), atom(), term(), list(), map()) :: :ok
  def exception(nil, _kind, _reason, _stacktrace, _signal_meta), do: :ok

  def exception(
        %{metadata: metadata, start_mono: start_mono},
        kind,
        reason,
        stacktrace,
        signal_meta
      ) do
    :telemetry.execute(
      @exception_event,
      %{
        duration: System.monotonic_time(:nanosecond) - start_mono,
        system_time: System.system_time(:nanosecond)
      },
      metadata
      |> Map.put(:result_status, :error)
      |> Map.put(:error_kind, kind)
      |> Map.put(:error_reason, inspect(reason))
      |> Map.put(:error_stacktrace, Exception.format_stacktrace(stacktrace))
      |> merge_signal_meta(signal_meta)
    )
  end

  defp result_status({:ok, _}), do: :ok
  defp result_status({:error, _}), do: :error
  defp result_status(_), do: :ok

  defp merge_signal_meta(metadata, signal_meta) do
    failed = Map.get(signal_meta, :failed, [])

    metadata
    |> Map.put(:signal_sent_count, Map.get(signal_meta, :sent, 0))
    |> Map.put(:signal_failed_count, length(failed))
    |> maybe_put_failures(failed)
  end

  defp maybe_put_failures(metadata, []), do: metadata
  defp maybe_put_failures(metadata, failures), do: Map.put(metadata, :signal_failures, failures)
end
