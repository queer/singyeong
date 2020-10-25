defmodule Singyeong.Store.Client do
  @moduledoc false

  use TypedStruct
  alias Singyeong.Store

  typedstruct enforce: true do
    field :app_id, Store.app_id()
    field :client_id, Store.client_id()
    field :metadata, map()
    field :socket_pid, pid()
    field :socket_ip, String.t() | nil
    field :queues, [atom()]
  end
end
