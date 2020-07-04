defmodule Coordinator do
  use GenServer

  @type via_tuple() :: {:via, atom(), {atom(), String.t()}}

  defmodule State do
    use TypedStruct

    typedstruct enforce: true do
      field :current_game, Coordinator.via_tuple() | none()
      field :queue, Qex.t(Coordinator.via_tuple())
    end
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{current_game: nil, queue: Qex.new()}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:terminate, id}, state) do
    GenServer.stop(via_tuple(id))

    state =
      if state.current_game == via_tuple(id) do
        %State{state | current_game: nil}
      else
        %State{state | queue: Qex.new(Enum.filter(state.queue, fn x -> x != via_tuple(id) end))}
      end

    Phoenix.PubSub.broadcast(
      InfolabLightGames.PubSub,
      "coordinator:status",
      {:game_terminate, id}
    )

    {:noreply, state, {:continue, :tick}}
  end

  @impl true
  def handle_cast({:route_input, player, input}, state) do
    if not is_nil(state.current_game) do
      GenServer.cast(state.current_game, {:handle_input, player, input})
    end
  end

  defp is_game_ready?(game) do
    GenServer.call(game, :get_status).ready
  end

  defp remove_first_ready(queue) do
    case Enum.find_index(queue, &is_game_ready?/1) do
      nil -> {:empty, queue}
      idx ->
        s = Enum.take(queue, idx)
        [e | t] = Enum.drop(queue, idx)
        {{:value, e}, Qex.join(Qex.new(s), Qex.new(t))}
    end
  end

  @impl true
  def handle_call({:queue_game, game, initial_player}, _from, state) do
    id =
      ?a..?z
      |> Enum.take_random(6)
      |> List.to_string()

    {:ok, _pid} =
      DynamicSupervisor.start_child(GameManager, {game, game_id: id, name: via_tuple(id)})

    :ok = GenServer.call(via_tuple(id), {:add_player, initial_player})

    state = update_in(state.queue, &Qex.push(&1, via_tuple(id)))

    {:reply, id, state, {:continue, :tick}}
  end

  @impl true
  def handle_call({:join_game, id, player}, _from, state) do
    :ok = GenServer.call(via_tuple(id), {:add_player, player})

    {:reply, id, state, {:continue, :tick}}
  end

  @impl true
  def handle_call({:leave_game, id, player}, _from, state) do
    :ok = GenServer.call(via_tuple(id), {:remove_player, player})

    {:reply, id, state, {:continue, :tick}}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, get_status(state), state}
  end

  @impl true
  def handle_continue(:tick, state) do
    state =
      if is_nil(state.current_game) do
        case remove_first_ready(state.queue) do
          {{:value, game}, q} ->
            %State{state | current_game: game, queue: q}

          {:empty, q} ->
            %State{state | queue: q}
        end
      else
        state
      end

    if not is_nil(state.current_game) do
      GenServer.call(state.current_game, :start_if_ready)
    end

    push_status(state)

    {:noreply, state}
  end

  defp push_status(state) do
    Phoenix.PubSub.broadcast(
      InfolabLightGames.PubSub,
      "coordinator:status",
      {:coordinator_update, get_status(state)}
    )
  end

  defp get_status(state) do
    current =
      if not is_nil(state.current_game),
        do: GenServer.call(state.current_game, :get_status)

    queue = Enum.map(state.queue, &GenServer.call(&1, :get_status))

    %CoordinatorStatus{current_game: current, queue: queue}
  end

  defp via_tuple(id) do
    {:via, Registry, {GameRegistry, id}}
  end

  def terminate_game(id) do
    GenServer.cast(__MODULE__, {:terminate, id})
  end

  def route_input(player, input) do
    GenServer.cast(__MODULE__, {:route_input, player, input})
  end

  def queue_game(game, initial_player) do
    GenServer.call(__MODULE__, {:queue_game, game, initial_player})
  end

  def join_game(id, player) do
    GenServer.call(__MODULE__, {:join_game, id, player})
  end

  def leave_game(id, player) do
    GenServer.call(__MODULE__, {:leave_game, id, player})
  end

  def status do
    GenServer.call(__MODULE__, :get_status)
  end
end