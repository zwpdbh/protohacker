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
    {:ok, camera1} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: true])
    {:ok, camera2} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: true])
    {:ok, dispatcher} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: true])

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
    {:ok, camera1} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: true])
    {:ok, camera2} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: true])

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

  # # --- NEW TESTS BELOW ---
  # test "sends tickets for two different cars on same day" do
  #   {:ok, camera1} = :gen_tcp.connect(@host, @port, [:binary, active: true])
  #   {:ok, camera2} = :gen_tcp.connect(@host, @port, [:binary, active: true])
  #   {:ok, camera3} = :gen_tcp.connect(@host, @port, [:binary, active: true])
  #   {:ok, camera4} = :gen_tcp.connect(@host, @port, [:binary, active: true])
  #   {:ok, disp} = :gen_tcp.connect(@host, @port, [:binary, active: true])

  #   # Car 1: ABC123
  #   send_message(camera1, %IAmCamera{
  #     road: 100,
  #     mile: 10,
  #     limit: 50
  #   })

  #   # Day 0, 100 sec in
  #   send_message(camera1, %Plate{
  #     plate: "ABC123",
  #     timestamp: day(0) + sec(100)
  #   })

  #   send_message(camera2, %IAmCamera{
  #     road: 100,
  #     mile: 11,
  #     limit: 50
  #   })

  #   send_message(camera2, %Plate{
  #     plate: "ABC123",
  #     timestamp: day(0) + sec(110)
  #   })

  #   # Car 2: XYZ789
  #   send_message(camera3, %IAmCamera{road: 100, mile: 20, limit: 50})
  #   send_message(camera3, %Plate{plate: "XYZ789", timestamp: day(0) + sec(200)})

  #   send_message(camera4, %IAmCamera{
  #     road: 100,
  #     mile: 21,
  #     limit: 50
  #   })

  #   send_message(camera4, %Plate{
  #     plate: "XYZ789",
  #     timestamp: day(0) + sec(210)
  #   })

  #   # Dispatcher for road 100
  #   send_message(disp, %IAmDispatcher{
  #     roads: [100]
  #   })

  #   # Should receive two tickets
  #   assert_receive {:tcp, ^disp, data1}
  #   assert {:ok, ticket1, remaining} = Message.decode(data1)

  #   assert_receive {:tcp, ^disp, data2}
  #   assert {:ok, ticket2, <<>>} = Message.decode(remaining <> data2)

  #   plates = Enum.sort([ticket1.plate, ticket2.plate])
  #   assert plates == ["ABC123", "XYZ789"]
  # end

  # test "does not send second ticket for same car on same day" do
  #   # Car: DU63QJJ
  #   {:ok, cam1a} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(cam1a, %{road: 200, mile: 5, limit: 50})
  #   # Day 0
  #   send_plate(cam1a, "DU63QJJ", day(0) + sec(1000))

  #   {:ok, cam1b} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(cam1b, %{road: 200, mile: 6, limit: 50})
  #   send_plate(cam1b, "DU63QJJ", day(0) + sec(1010))

  #   # Second violation on same day
  #   {:ok, cam2a} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(cam2a, %{road: 200, mile: 15, limit: 50})
  #   send_plate(cam2a, "DU63QJJ", day(0) + sec(2000))

  #   {:ok, cam2b} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(cam2b, %{road: 200, mile: 16, limit: 50})
  #   send_plate(cam2b, "DU63QJJ", day(0) + sec(2010))

  #   # Dispatcher
  #   {:ok, disp} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_dispatcher(disp, [200])

  #   # Should receive only **one** ticket for DU63QJJ
  #   assert {:ok, ticket_data} = :gen_tcp.recv(disp, 0, 5000)
  #   {:ok, ticket, _} = Protohacker.SpeedDaemon.Message.decode(ticket_data)
  #   assert ticket.plate == "DU63QJJ"

  #   # No second ticket
  #   assert {:error, :timeout} = :gen_tcp.recv(disp, 0, 500)

  #   # Clean up
  #   Enum.each([cam1a, cam1b, cam2a, cam2b, disp], &:gen_tcp.close/1)
  # end

  # test "sends two tickets for same car on different days" do
  #   # Violation 1: Day 0
  #   {:ok, cam1a} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(cam1a, %{road: 300, mile: 1, limit: 50})
  #   send_plate(cam1a, "SAMECAR", day(0) + sec(100))

  #   {:ok, cam1b} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(cam1b, %{road: 300, mile: 2, limit: 50})
  #   send_plate(cam1b, "SAMECAR", day(0) + sec(110))

  #   # Violation 2: Day 1
  #   {:ok, cam2a} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(cam2a, %{road: 300, mile: 10, limit: 50})
  #   send_plate(cam2a, "SAMECAR", day(1) + sec(100))

  #   {:ok, cam2b} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(cam2b, %{road: 300, mile: 11, limit: 50})
  #   send_plate(cam2b, "SAMECAR", day(1) + sec(110))

  #   # Dispatcher
  #   {:ok, disp} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_dispatcher(disp, [300])

  #   # Should receive two tickets
  #   assert {:ok, ticket1_data} = :gen_tcp.recv(disp, 0, 5000)
  #   assert {:ok, ticket2_data} = :gen_tcp.recv(disp, 0, 5000)

  #   {:ok, ticket1, _} = Protohacker.SpeedDaemon.Message.decode(ticket1_data)
  #   {:ok, ticket2, _} = Protohacker.SpeedDaemon.Message.decode(ticket2_data)

  #   assert ticket1.plate == "SAMECAR"
  #   assert ticket2.plate == "SAMECAR"

  #   # Clean up
  #   Enum.each([cam1a, cam1b, cam2a, cam2b, disp], &:gen_tcp.close/1)
  # end

  # test "ticket spanning two days blocks both days for same car" do
  #   # Long violation spanning midnight
  #   {:ok, cam1a} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(cam1a, %{road: 400, mile: 5, limit: 50})
  #   # Just before midnight
  #   send_plate(cam1a, "DAYSPANS", day(0) + sec(86390))

  #   {:ok, cam1b} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(cam1b, %{road: 400, mile: 6, limit: 50})
  #   # Just after midnight
  #   send_plate(cam1b, "DAYSPANS", day(1) + sec(10))

  #   # Now try to send another violation on day 1
  #   {:ok, cam2a} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(cam2a, %{road: 400, mile: 15, limit: 50})
  #   send_plate(cam2a, "DAYSPANS", day(1) + sec(1000))

  #   {:ok, cam2b} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(cam2b, %{road: 400, mile: 16, limit: 50})
  #   send_plate(cam2b, "DAYSPANS", day(1) + sec(1010))

  #   # Dispatcher
  #   {:ok, disp} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_dispatcher(disp, [400])

  #   # Only one ticket should be sent (for the span)
  #   assert {:ok, ticket_data} = :gen_tcp.recv(disp, 0, 5000)
  #   {:ok, ticket, _} = Protohacker.SpeedDaemon.Message.decode(ticket_data)
  #   assert ticket.plate == "DAYSPANS"

  #   # No second ticket for day 1
  #   assert {:error, :timeout} = :gen_tcp.recv(disp, 0, 500)

  #   # Clean up
  #   Enum.each([cam1a, cam1b, cam2a, cam2b, disp], &:gen_tcp.close/1)
  # end

  # test "sends heartbeats at requested interval" do
  #   # Connect a camera
  #   {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(socket, %{road: 456, mile: 10, limit: 50})

  #   # Request heartbeats every 2.5 seconds (25 deciseconds)
  #   interval_deciseconds = 25
  #   send_want_heartbeat(socket, interval_deciseconds)

  #   # Calculate expected interval in milliseconds
  #   expected_interval_ms = interval_deciseconds * 100
  #   # Allow a small margin of error (e.g., 100ms) for test timing
  #   tolerance_ms = 100

  #   # Receive the first heartbeat
  #   assert {:ok, hb1_data} = :gen_tcp.recv(socket, 0)
  #   first_heartbeat_time = System.monotonic_time(:millisecond)

  #   {:ok, %Protohacker.SpeedDaemon.Message.Heartbeat{}, _} =
  #     Protohacker.SpeedDaemon.Message.decode(hb1_data)

  #   # Receive the second heartbeat
  #   assert {:ok, hb2_data} = :gen_tcp.recv(socket, 0)
  #   second_heartbeat_time = System.monotonic_time(:millisecond)

  #   {:ok, %Protohacker.SpeedDaemon.Message.Heartbeat{}, _} =
  #     Protohacker.SpeedDaemon.Message.decode(hb2_data)

  #   # Measure the time between heartbeats
  #   elapsed_ms = second_heartbeat_time - first_heartbeat_time

  #   # The time between hb1 and hb2 should be ~2.5 seconds
  #   # Assert the elapsed time is within the expected range
  #   assert elapsed_ms >= expected_interval_ms - tolerance_ms
  #   assert elapsed_ms <= expected_interval_ms + tolerance_ms

  #   # Clean up
  #   :gen_tcp.close(socket)
  # end

  # test "sending WantHeartbeat twice is an error" do
  #   # Connect a camera
  #   {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
  #   send_ia_camera(socket, %{road: 789, mile: 15, limit: 70})

  #   # Send WantHeartbeat the first time (should be ok)
  #   # 1 second interval
  #   send_want_heartbeat(socket, 10)

  #   assert {:ok, _heartbeat} = :gen_tcp.recv(socket, 0)

  #   # Send WantHeartbeat the second time (should be an error)
  #   # Different interval
  #   send_want_heartbeat(socket, 20)

  #   # The server should send an Error message and close the connection
  #   assert {:ok, error_msg} = :gen_tcp.recv(socket, 0)

  #   {:ok, %Protohacker.SpeedDaemon.Message.Error{message: _error_msg}, _} =
  #     Protohacker.SpeedDaemon.Message.decode(error_msg)

  #   # The connection should now be closed
  #   assert {:error, _} = :gen_tcp.recv(socket, 0, 0)

  #   # Clean up (though already closed)
  #   :gen_tcp.close(socket)
  # end
end
