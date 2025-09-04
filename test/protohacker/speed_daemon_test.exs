defmodule Protohacker.SpeedDaemonTest do
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

  test "camera can send IAmCamera and Plate without disconnection" do
    # Start the server (assuming it's already started via setup, or start it)
    # This assumes your server listens on @port

    {:ok, camera} = :gen_tcp.connect(@host, @port, [:binary, active: true])

    send_message(camera, %Message.IAmCamera{
      road: 582,
      mile: 4452,
      limit: 100
    })

    # Wait a moment to ensure server processed it
    :timer.sleep(100)

    # Now send Plate on the same connection
    send_message(camera, %Message.Plate{
      plate: "TESTPLATE",
      timestamp: 1_000_000
    })

    # Wait to see if connection is dropped
    :timer.sleep(100)

    # Try to send another message (optional: test still alive)
    send_message(camera, %Message.Plate{
      plate: "TESTPLATE",
      timestamp: 1_000_000
    })

    # If we get here without crash, and no tcp_closed, it passed
    :gen_tcp.close(camera)
  end

  test "receives heartbeats at requested interval" do
    {:ok, client} = :gen_tcp.connect(@host, @port, [:binary, active: true])

    # Request heartbeat every 20 deciseconds = 2 seconds
    send_message(client, %Message.WantHeartbeat{interval: 20})

    # Allow time for 3 heartbeats: 2s apart → wait 7 seconds
    assert_receive {:tcp, ^client, data1}, 3000
    assert {:ok, %Message.Heartbeat{}, <<>>} = Message.decode(data1)

    assert_receive {:tcp, ^client, data2}, 3000
    assert {:ok, %Message.Heartbeat{}, <<>>} = Message.decode(data2)

    assert_receive {:tcp, ^client, data3}, 3000
    assert {:ok, %Message.Heartbeat{}, <<>>} = Message.decode(data3)

    # Close connection
    :gen_tcp.close(client)
  end

  test "disables heartbeats with interval 0" do
    {:ok, client} = :gen_tcp.connect(@host, @port, [:binary, active: true])

    # Enable heartbeats every 10 deciseconds (~1 second)
    send_message(client, %Message.WantHeartbeat{interval: 10})

    assert_receive {:tcp, ^client, _heartbeat1}, 1500
    assert_receive {:tcp, ^client, _heartbeat2}, 1500

    # Disable heartbeats
    send_message(client, %Message.WantHeartbeat{interval: 0})

    # Wait longer than interval — should NOT receive heartbeat
    refute_receive {:tcp, ^client, _any}, 2000

    :gen_tcp.close(client)
  end

  test "sending multiple WantHeartbeat is an error" do
    {:ok, client} = :gen_tcp.connect(@host, @port, [:binary, active: true])

    # First is OK
    send_message(client, %Message.WantHeartbeat{interval: 10})

    # Second should cause error → connection closed
    send_message(client, %Message.WantHeartbeat{interval: 5})

    # Expect connection to close
    assert_receive {:tcp_closed, ^client}, 1000

    :gen_tcp.close(client)
  end

  test "heartbeat interval of 25 sends every 2.5 seconds" do
    {:ok, client} = :gen_tcp.connect(@host, @port, [:binary, active: true])

    # 2.5 seconds
    send_message(client, %Message.WantHeartbeat{interval: 25})

    # First heartbeat
    assert_receive {:tcp, ^client, data1}, 3000
    assert {:ok, %Message.Heartbeat{}, <<>>} = Message.decode(data1)

    # Second heartbeat
    assert_receive {:tcp, ^client, data2}, 3000
    assert {:ok, %Message.Heartbeat{}, <<>>} = Message.decode(data2)

    # Rough timing: ~2.5s between, allow slack
    :gen_tcp.close(client)
  end
end
