defmodule MessageService.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [{Telemetry.Metrics.ConsoleReporter, metrics: metrics()}]
    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      counter("message.sent.count"),
      counter("message.delivered.count"),
      counter("message.read.count"),
      summary("message.send.duration", unit: {:native, :millisecond}),
      last_value("message.active_conversations.count"),
      counter("typing.started.count"),
      counter("reaction.added.count")
    ]
  end
end
