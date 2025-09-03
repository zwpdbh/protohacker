defmodule Protohacker.SpeedDaemon.SpeedDaemonTest do
  use ExUnit.Case

  alias Protohacker.SpeedDaemon.Message

  alias Protohacker.SpeedDaemon.Message.{
    Ticket,
    Plate,
    IAmDispatcher,
    IAmCamera
  }

  @host ~c"localhost"
  @port 5005

  defp sec(ds), do: ds
  # n days in seconds
  defp day(n), do: n * 24 * 60 * 60

  defp send_message(socket, message) do
    assert :ok = :gen_tcp.send(socket, Message.encode(message))
  end

  test "ticketing a single car" do
    {:ok, camera1} = :gen_tcp.connect(@host, @port, [:binary, active: true])
    {:ok, camera2} = :gen_tcp.connect(@host, @port, [:binary, active: true])
    {:ok, dispatcher} = :gen_tcp.connect(@host, @port, [:binary, active: true])

    send_message(dispatcher, %IAmDispatcher{roads: [582]})

    send_message(camera1, %IAmCamera{
      road: 582,
      mile: 4452,
      limit: 100
    })

    send_message(camera1, %Plate{
      plate: "UK43PKD",
      timestamp: 203_663
    })

    send_message(camera2, %IAmCamera{
      road: 582,
      mile: 4462,
      limit: 100
    })

    send_message(camera2, %Plate{
      plate: "UK43PKD",
      timestamp: 203_963
    })

    assert_receive {:tcp, ^dispatcher, data}
    assert {:ok, message, <<>>} = Message.decode(data)

    assert message == %Ticket{
             mile1: 4452,
             mile2: 4462,
             plate: "UK43PKD",
             road: 582,
             speed: 12000,
             timestamp1: 203_663,
             timestamp2: 203_963
           }
  end

  test "pending tickets get flushed" do
    {:ok, camera1} = :gen_tcp.connect(@host, @port, [:binary, active: true])
    {:ok, camera2} = :gen_tcp.connect(@host, @port, [:binary, active: true])

    send_message(camera1, %IAmCamera{
      road: 582,
      mile: 4452,
      limit: 100
    })

    send_message(camera2, %IAmCamera{
      road: 582,
      mile: 4462,
      limit: 100
    })

    send_message(camera1, %Plate{
      plate: "IT43PRC",
      timestamp: 203_663
    })

    send_message(camera2, %Plate{
      plate: "IT43PRC",
      timestamp: 203_963
    })

    # We now have a tickets on road 582, but no dispatcher for it.
    {:ok, dispatcher} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: true])
    send_message(dispatcher, %IAmDispatcher{roads: [582]})

    assert_receive {:tcp, ^dispatcher, data}, 20_000
    assert {:ok, message, <<>>} = Message.decode(data)

    assert message == %Ticket{
             mile1: 4452,
             mile2: 4462,
             plate: "IT43PRC",
             road: 582,
             speed: 12000,
             timestamp1: 203_663,
             timestamp2: 203_963
           }
  end

  test "generates ticket for speeding car and sends to dispatcher" do
    # Connect camera 1
    {:ok, camera1} = :gen_tcp.connect(@host, @port, [:binary, active: true])
    {:ok, camera2} = :gen_tcp.connect(@host, @port, [:binary, active: true])
    {:ok, dispatcher} = :gen_tcp.connect(@host, @port, [:binary, active: true])

    send_message(camera1, %IAmCamera{
      road: 123,
      mile: 8,
      limit: 60
    })

    send_message(camera1, %Plate{
      plate: "UN1X",
      timestamp: 0
    })

    send_message(camera2, %IAmCamera{
      road: 123,
      mile: 9,
      limit: 60
    })

    send_message(camera2, %Plate{
      plate: "UN1X",
      timestamp: 45
    })

    send_message(dispatcher, %IAmDispatcher{
      roads: [123]
    })

    assert_receive {:tcp, ^dispatcher, data}
    assert {:ok, message, <<>>} = Message.decode(data)

    assert message == %Ticket{
             plate: "UN1X",
             road: 123,
             mile1: 8,
             timestamp1: 0,
             mile2: 9,
             timestamp2: 45,
             speed: 8000
           }
  end

  test "sends tickets for two different cars on same day" do
    {:ok, camera1} = :gen_tcp.connect(@host, @port, [:binary, active: true])
    {:ok, camera2} = :gen_tcp.connect(@host, @port, [:binary, active: true])
    {:ok, camera3} = :gen_tcp.connect(@host, @port, [:binary, active: true])
    {:ok, camera4} = :gen_tcp.connect(@host, @port, [:binary, active: true])
    {:ok, disp} = :gen_tcp.connect(@host, @port, [:binary, active: true])

    # Car 1: ABC123
    send_message(camera1, %IAmCamera{
      road: 100,
      mile: 10,
      limit: 50
    })

    # Day 0, 100 sec in
    send_message(camera1, %Plate{
      plate: "ABC123",
      timestamp: day(0) + sec(100)
    })

    send_message(camera2, %IAmCamera{
      road: 100,
      mile: 11,
      limit: 50
    })

    send_message(camera2, %Plate{
      plate: "ABC123",
      timestamp: day(0) + sec(110)
    })

    # Car 2: XYZ789
    send_message(camera3, %IAmCamera{road: 100, mile: 20, limit: 50})
    send_message(camera3, %Plate{plate: "XYZ789", timestamp: day(0) + sec(200)})

    send_message(camera4, %IAmCamera{
      road: 100,
      mile: 21,
      limit: 50
    })

    send_message(camera4, %Plate{
      plate: "XYZ789",
      timestamp: day(0) + sec(210)
    })

    # Dispatcher for road 100
    send_message(disp, %IAmDispatcher{
      roads: [100]
    })

    # Should receive two tickets
    assert_receive {:tcp, ^disp, data1}
    assert {:ok, ticket1, remaining} = Message.decode(data1)

    assert_receive {:tcp, ^disp, data2}
    assert {:ok, ticket2, <<>>} = Message.decode(remaining <> data2)

    plates = Enum.sort([ticket1.plate, ticket2.plate])
    assert plates == ["ABC123", "XYZ789"]
  end
end
