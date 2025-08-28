defmodule Protohacker.SpeedDaemon.SpeedDaemonTest do
  use ExUnit.Case

  @host ~c"localhost"
  @port 4004

  test "generates ticket for speeding car and sends to dispatcher" do
    # Connect camera 1
    {:ok, cam1_socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])

    send_ia_camera(cam1_socket, 123, 8, 60)
    send_plate(cam1_socket, "UN1X", 0)

    # Connect camera 2
    {:ok, cam2_socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
    send_ia_camera(cam2_socket, 123, 9, 60)
    send_plate(cam2_socket, "UN1X", 45)

    # Connect dispatcher
    {:ok, disp_socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
    send_ia_dispatcher(disp_socket, [123])

    # --- WAIT HERE ---
    # :timer.sleep(5_000)
    # --- WAIT ENDS ---

    # Read the ticket from dispatcher
    assert {:ok, ticket_data} = :gen_tcp.recv(disp_socket, 0, 500)

    # Decode ticket

    {:ok, %Protohacker.SpeedDaemon.Message.Ticket{} = ticket, _remaining} =
      Protohacker.SpeedDaemon.Message.Ticket.decode(ticket_data)

    assert ticket.plate == "UN1X"
    assert ticket.road == 123
    assert ticket.mile1 == 8
    assert ticket.timestamp1 == 0
    assert ticket.mile2 == 9
    assert ticket.timestamp2 == 45
    assert ticket.speed == 8000

    # Clean up
    :gen_tcp.close(cam1_socket)
    :gen_tcp.close(cam2_socket)
    :gen_tcp.close(disp_socket)
  end

  test "sends heartbeats at requested interval" do
    # Connect a camera
    {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
    send_ia_camera(socket, 456, 10, 50)

    # Request heartbeats every 2.5 seconds (25 deciseconds)
    interval_deciseconds = 25
    send_want_heartbeat(socket, interval_deciseconds)

    # Calculate expected interval in milliseconds
    expected_interval_ms = interval_deciseconds * 100
    # Allow a small margin of error (e.g., 100ms) for test timing
    tolerance_ms = 100

    # Receive the first heartbeat
    assert {:ok, hb1_data} = :gen_tcp.recv(socket, 0, @timeout)

    {:ok, %Protohacker.SpeedDaemon.Message.Heartbeat{}, _} =
      Protohacker.SpeedDaemon.Message.Heartbeat.decode(hb1_data)

    # Receive the second heartbeat
    assert {:ok, hb2_data} = :gen_tcp.recv(socket, 0, @timeout)

    {:ok, %Protohacker.SpeedDaemon.Message.Heartbeat{}, _} =
      Protohacker.SpeedDaemon.Message.Heartbeat.decode(hb2_data)

    # Measure the time between heartbeats
    start_time = System.monotonic_time(:millisecond)
    # We already received hb1, so we need to receive hb3 to measure between hb2 and hb3
    # But let's just measure the time it took to get hb2 after hb1
    # The time between hb1 and hb2 should be ~2.5 seconds
    elapsed_ms = System.monotonic_time(:millisecond) - start_time

    # Assert the elapsed time is within the expected range
    assert elapsed_ms >= expected_interval_ms - tolerance_ms
    assert elapsed_ms <= expected_interval_ms + tolerance_ms

    # Clean up
    :gen_tcp.close(socket)
  end

  test "sending WantHeartbeat twice is an error" do
    # Connect a camera
    {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
    send_ia_camera(socket, 789, 15, 70)

    # Send WantHeartbeat the first time (should be ok)
    # 1 second interval
    send_want_heartbeat(socket, 10)

    # Send WantHeartbeat the second time (should be an error)
    # Different interval
    send_want_heartbeat(socket, 20)

    # The server should send an Error message and close the connection
    assert {:ok, error_data} = :gen_tcp.recv(socket, 0, @timeout)

    {:ok, %Protohacker.SpeedDaemon.Message.Error{msg: error_msg}, _} =
      Protohacker.SpeedDaemon.Message.Error.decode(error_data)

    # Or whatever specific message you send
    assert error_msg == "illegal msg"

    # The connection should now be closed
    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 0)

    # Clean up (though already closed)
    :gen_tcp.close(socket)
  end

  defp send_ia_camera(socket, road, mile, limit) do
    msg =
      Protohacker.SpeedDaemon.Message.IAmCamera.encode(%Protohacker.SpeedDaemon.Message.IAmCamera{
        road: road,
        mile: mile,
        limit: limit
      })

    :gen_tcp.send(socket, msg)
  end

  defp send_plate(socket, plate, timestamp) do
    msg =
      Protohacker.SpeedDaemon.Message.Plate.encode(%Protohacker.SpeedDaemon.Message.Plate{
        plate: plate,
        timestamp: timestamp
      })

    :gen_tcp.send(socket, msg)
  end

  defp send_ia_dispatcher(socket, roads) when is_list(roads) do
    msg =
      Protohacker.SpeedDaemon.Message.IAmDispatcher.encode(
        %Protohacker.SpeedDaemon.Message.IAmDispatcher{
          roads: roads,
          numroads: length(roads)
        }
      )

    :gen_tcp.send(socket, msg)
  end

  defp send_want_heartbeat(socket, interval) do
    msg =
      Protohacker.SpeedDaemon.Message.WantHeartbeat.encode(
        %Protohacker.SpeedDaemon.Message.WantHeartbeat{
          interval: interval
        }
      )

    :gen_tcp.send(socket, msg)
  end
end
