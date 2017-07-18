defmodule HoneydewTest do
  use ExUnit.Case
  alias Honeydew.Job

  test "queue_spec/2" do
    queue = :erlang.unique_integer

    spec =
      Honeydew.queue_spec(
        queue,
        queue: {:abc, [1,2,3]},
        dispatcher: {Dis.Patcher, [:a, :b]},
        failure_mode: {Fail.Ure, [:a, :b]},
        success_mode: {Succ.Ess, [:a, :b]},
        supervisor_opts: [id: :my_queue_supervisor])

    assert spec == {:my_queue_supervisor,
                    {Honeydew.QueueSupervisor, :start_link,
                     [queue, :abc, [1, 2, 3], 1, {Dis.Patcher, [:a, :b]},
                      {Fail.Ure, [:a, :b]}, {Succ.Ess, [:a, :b]}]}, :permanent, :infinity, :supervisor,
                    [Honeydew.QueueSupervisor]}
  end

  test "queue_spec/2 defaults" do
    queue = :erlang.unique_integer
    spec =  Honeydew.queue_spec(queue)

    assert spec == {{:queue, queue},
                    {Honeydew.QueueSupervisor, :start_link,
                     [queue, Honeydew.Queue.ErlangQueue, [], 1,
                      {Honeydew.Dispatcher.LRU, []}, {Honeydew.FailureMode.Abandon, []}, nil]},
                    :permanent, :infinity, :supervisor, [Honeydew.QueueSupervisor]}

    queue = {:global, :erlang.unique_integer}
    spec =  Honeydew.queue_spec(queue)

    assert spec == {{:queue, queue},
                    {Honeydew.QueueSupervisor, :start_link,
                     [queue, Honeydew.Queue.ErlangQueue, [], 1,
                      {Honeydew.Dispatcher.LRUNode, []}, {Honeydew.FailureMode.Abandon, []}, nil]},
                    :permanent, :infinity, :supervisor, [Honeydew.QueueSupervisor]}
  end

  test "worker_spec/2" do
    queue = :erlang.unique_integer

    spec = Honeydew.worker_spec(
      queue,
      {Worker, [1, 2, 3]},
      num: 123,
      init_retry_secs: 5,
      supervisor_opts: [id: :my_worker_supervisor])

    assert spec == {:my_worker_supervisor,
                    {Honeydew.WorkerGroupSupervisor, :start_link,
                     [queue, Worker, [1, 2, 3], 123, 5, 10_000, []]}, :permanent,
                    :infinity, :supervisor, [Honeydew.WorkerGroupSupervisor]}
  end

  test "worker_spec/2 defaults" do
    queue = :erlang.unique_integer

    spec =  Honeydew.worker_spec(queue, Worker)
    assert spec == {{:worker, queue},
                    {Honeydew.WorkerGroupSupervisor, :start_link,
                     [queue, Worker, [], 10, 5, 10000, []]}, :permanent, :infinity,
                    :supervisor, [Honeydew.WorkerGroupSupervisor]}
  end

  test "group/1" do
    assert Honeydew.group(:my_queue, :workers) == :"honeydew.workers.my_queue"
  end

  test "supervisor/1" do
    assert Honeydew.supervisor(:my_queue, :worker) == :"honeydew.worker_supervisor.my_queue"
  end

  test "supervisor/1 with global queue" do
    assert Honeydew.supervisor({:global, :my_queue}, :worker) == :"honeydew.worker_supervisor.global.my_queue"
  end

  test "success mode smoke test" do
    queue = :erlang.unique_integer
    {:ok, _} = Helper.start_queue_link(queue, success_mode: {TestSuccessMode, [to: self()]})
    {:ok, _} = Helper.start_worker_link(queue, Stateless)

    %Job{private: id} = fn -> :noop end |> Honeydew.async(queue)

    assert_receive %Job{private: ^id}
  end

  test "progress updates" do
    queue = :erlang.unique_integer
    {:ok, _} = Helper.start_queue_link(queue)
    {:ok, _} = Helper.start_worker_link(queue, Stateless)

    {:emit_progress, ["doing thing 1/2"]} |> Honeydew.async(queue)

    [{_worker, {_job, status}}] =
      queue
      |> Honeydew.status
      |> Map.get(:workers)
      |> Enum.filter(fn {pid, {job, status}} -> true
                                          _ -> false end)

    assert status == {:running, "doing thing 1/2"}
  end

end
