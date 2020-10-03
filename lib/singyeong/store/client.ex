defmodule Singyeong.Store.Client do
  use TypedStruct

  typedstruct enforce: true do
    field :app_id, String.t()
    field :client_id, String.t()
    field :metadata, map()
    field :socket_pid, pid()
    field :socket_ip, String.t() | nil
    field :queues, [atom()]
  end
end
