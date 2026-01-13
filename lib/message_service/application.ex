defmodule MessageService.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MessageService.Telemetry,
      {Phoenix.PubSub, name: MessageService.PubSub},
      {Mongo, [
        name: :message_mongo,
        url: Application.get_env(:message_service, :mongodb)[:url],
        pool_size: Application.get_env(:message_service, :mongodb)[:pool_size] || 10
      ]},
      {Redix, [
        host: Application.get_env(:message_service, :redis)[:host],
        port: Application.get_env(:message_service, :redis)[:port],
        database: Application.get_env(:message_service, :redis)[:database] || 5,
        name: :message_redis
      ]},
      {Horde.Registry, [name: MessageService.ConversationRegistry, keys: :unique]},
      {Horde.DynamicSupervisor, [name: MessageService.ConversationSupervisor, strategy: :one_for_one]},
      MessageService.MessageManager,
      MessageService.TypingTracker,
      {Cluster.Supervisor, [Application.get_env(:libcluster, :topologies), [name: MessageService.ClusterSupervisor]]},
      MessageService.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MessageService.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MessageService.Endpoint.config_change(changed, removed)
    :ok
  end
end
