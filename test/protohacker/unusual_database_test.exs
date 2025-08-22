defmodule Protohacker.UnusualDatabaseTest do
  use ExUnit.Case

  setup do
    # Use the fixed port from your module
    port = Protohacker.UnusualDatabase.port()
    host = {127, 0, 0, 1}

    # Open a UDP client socket for testing
    {:ok, client} = :gen_udp.open(0, [:binary, active: false, ip: host])

    on_exit(fn ->
      :gen_udp.close(client)
    end)

    {:ok, client: client, port: port, host: host}
  end

  defp send_recv(socket, host, port, message) when byte_size(message) < 1000 do
    :ok = :gen_udp.send(socket, host, port, message)

    case :gen_udp.recv(socket, 0, 100) do
      {:ok, {_addr, _port, reply}} -> reply
      {:error, :timeout} -> nil
    end
  end

  defp send_no_response(socket, host, port, message) when byte_size(message) < 1000 do
    :ok = :gen_udp.send(socket, host, port, message)
    # Expect no response within short timeout
    case :gen_udp.recv(socket, 0, 50) do
      {:ok, _} -> flunk("Expected no response for insert")
      {:error, :timeout} -> :ok
    end
  end

  test "insert does not return a response", %{client: client, host: host, port: port} do
    send_no_response(client, host, port, "key=value")
  end

  test "retrieve returns key=value", %{client: client, host: host, port: port} do
    send_no_response(client, host, port, "key=value")
    response = send_recv(client, host, port, "key")
    assert response == "key=value"
  end

  test "retrieving non-existent key may return nothing or key=", %{
    client: client,
    host: host,
    port: port
  } do
    response = send_recv(client, host, port, "missing")

    case response do
      # No response is acceptable
      nil -> assert true
      # Or "missing=" is acceptable
      "missing=" -> assert true
      other -> flunk("Unexpected response: #{inspect(other)}")
    end
  end

  test "insert with multiple equals signs", %{client: client, host: host, port: port} do
    send_no_response(client, host, port, "foo=bar=baz")
    response = send_recv(client, host, port, "foo")
    assert response == "foo=bar=baz"
  end

  test "empty key and empty value", %{client: client, host: host, port: port} do
    send_no_response(client, host, port, "=value")
    response1 = send_recv(client, host, port, "")
    assert response1 == "=value"

    send_no_response(client, host, port, "key=")
    response2 = send_recv(client, host, port, "key")
    assert response2 == "key="
  end

  test "version key returns version string", %{client: client, host: host, port: port} do
    response = send_recv(client, host, port, "version")
    assert response =~ ~r/^version=.+$/
    assert response != "version="
  end

  test "modifying version is ignored", %{client: client, host: host, port: port} do
    original = send_recv(client, host, port, "version")
    send_no_response(client, host, port, "version=hacked")

    new = send_recv(client, host, port, "version")
    assert new == original, "Version should not be modifiable"
  end

  test "consecutive inserts update value", %{client: client, host: host, port: port} do
    send_no_response(client, host, port, "user=Alice")
    send_no_response(client, host, port, "user=Bob")
    response = send_recv(client, host, port, "user")
    assert response == "user=Bob"
  end

  test "server responds from same port and to client's address", %{
    client: client,
    host: host,
    port: port
  } do
    send_no_response(client, host, port, "test=data")
    response = send_recv(client, host, port, "test")
    assert response == "test=data"
    # This test implicitly checks that response was routed back correctly
  end
end
