defmodule CtUtil do

  def hostname do
    {name, 0} = System.cmd("hostname", [])
    String.strip(name)
  end

  def node_name(name), do: :"#{name}@#{hostname()}"

  def gen_setup(context) do
    case File.dir?("./data") do
      true -> File.rm_rf("./data")
      false -> :ok
    end
    :ok == File.mkdir("./data")
    :ok = Application.start(:crdtex)
    :ok = Application.start(:supervisorring)

    start_ring =
      fn(name) -> {:ok, _} = GenServerring.start_link({name, TesterRing}) end
    rings = context.ring_names
    Enum.each(rings, start_ring)
    DHTGenServer.add_rings(rings)
  end

end

# one app with 6 clients on one ring and 6 other clients on an other ring
defmodule MyApp do
  use Application

  defmodule SupRing do # stuff common to the 2 supervisor rings

    def migrate({_, _, _}, old, new),
      do: GenServer.cast(new, GenServer.call(old, :get))

    def client_spec(name) do
      {name,
        {:gen_server, :start_link, [{:local, name}, GenericServer, nil, []]},
        :permanent, 2, :worker, [GenericServer]}
    end

    def init(sup_name, ring_name, module, clients \\ ["C1", "C2"]) do
      children = for c <- clients, do: client_spec(:"#{sup_name}.#{c}")
      {:ok,
        {
          {:one_for_one, 2, 3},
          [{:dyn_child_handler, module} | children],
          ring_name
        }
      }
    end

    def add(childspec, file) do
      File.write!(
        file,
        File.read!()
        |> :erlang.binary_to_term
        |> List.insert_at(0, childspec)
        |> :erlang.term_to_binary)
    end

    def del(childid, file) do
      File.write!(
        file,
        File.read!(file)
        |> :erlang.binary_to_term
        |> List.keydelete(childid, 0)
        |> :erlang.term_to_binary)
    end
  end # MyApp.SupRing

  defmodule SupRing1 do
    use Supervisorring

    def migrate(a, b, c), do: MyApp.SupRing.migrate(a, b, c)
    def init(ring_name) do
      MyApp.SupRing.init(__MODULE__, ring_name, __MODULE__,
        ["C1", "C2", "C3", "C4", "C5", "C6"])
    end
    @behaviour :dyn_child_handler
    def match(_), do: true
    def get_all, do: "childs_1" |> File.read! |> :erlang.binary_to_term
    def add(childspec), do: MyApp.SupRing.add(childspec, "childs_1")
    def del(childspec), do: MyApp.SupRing.del(childspec, "childs_1")
    def start_link(sup_name) do
      :supervisorring.start_link(sup_name, __MODULE__, :test_ring1)
    end
  end # MyApp.SupRing1

  defmodule SupRing2 do
    use Supervisorring

    def migrate(a, b, c), do: MyApp.SupRing.migrate(a, b, c)
    def init(ring_name) do
      MyApp.SupRing.init(__MODULE__, ring_name, __MODULE__,
        ["C1", "C2", "C3", "C4", "C5", "C6"])
    end
    @behaviour :dyn_child_handler
    def match(_), do: true
    def get_all, do: "childs_2" |> File.read! |> :erlang.binary_to_term
    def add(childspec), do: MyApp.SupRing.add(childspec, "childs_2")
    def del(childspec), do: MyApp.SupRing.del(childspec, "childs_2")
    def start_link(sup_name) do
      :supervisorring.start_link(sup_name, __MODULE__, :test_ring2)
    end
  end # MyApp.SupRing2

  def start(_type, args),
    do: Supervisor.start_link(MyApp.Sup, args)

  defmodule Sup do
    use Supervisor

    def init(_) do
      wrk =
        fn(sup_name) ->
          worker(sup_name, [{:local, sup_name}], id: sup_name)
        end
      children = [wrk.(MyApp.SupRing1), wrk.(MyApp.SupRing2)]
      supervise(children, strategy: :one_for_one)
    end
  end
end
