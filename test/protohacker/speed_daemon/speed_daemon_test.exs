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
end
