defmodule Protohacker.MobMiddleTest do
  use ExUnit.Case

  @proxy_port 4003

  defp connect(port) do
    :gen_tcp.connect(~c"localhost", port, [:binary, packet: :line, active: false])
  end

  defp send_message(socket, message) when is_binary(message) do
    :gen_tcp.send(socket, message <> "\n")
  end

  defp recv_message(socket, timeout \\ 500) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} -> String.trim_trailing(data, "\n")
      other -> other
    end
  end

  setup do
    # Ensure the app is started (BudgetChat and MobMiddle are running)
    Application.ensure_all_started(:protohacker)

    # Give servers time to bind
    :timer.sleep(100)

    {:ok, proxy_socket} = connect(@proxy_port)
    {:ok, proxy_socket: proxy_socket}
  end

  test "case01 -- MobMiddle plays the role of BudgetChat server", %{proxy_socket: proxy_socket} do
    # 1. Client should receive welcome message from proxy (originating from BudgetChat)
    assert recv_message(proxy_socket) == "Welcome to budgetchat! What shall I call you?"

    # 2. Send username
    send_message(proxy_socket, "bob")

    # 3. Should receive room occupants (could be empty or contain others)
    assert recv_message(proxy_socket) =~ ~r{\* The room contains:.*}
  end

  # test "case02 -- rewrites Boguscoin address in message from client", %{proxy_socket: client} do
  #   # Skip welcome and name
  #   assert recv_message(client) == "Welcome to budgetchat! What shall I call you?"
  #   send_message(client, "bob")
  #   # room list
  #   _ = recv_message(client)

  #   # Send message with victim's Boguscoin address
  #   victim_addr = "7iKDZEwPZSqIvDnHvVN2r0hUWXD5rHX"
  #   send_message(client, "Please send payment to #{victim_addr}")

  #   # Proxy should rewrite it before sending to BudgetChat
  #   # So BudgetChat server will see message with Tony's address

  #   # Now connect directly to BudgetChat server to observe the message
  #   {:ok, server_client} = connect(@budget_chat_port)
  #   assert recv_message(server_client) == "Welcome to budgetchat! What shall I call you?"
  #   send_message(server_client, "observer")
  #   _ = recv_message(server_client)

  #   # Wait for message
  #   :timer.sleep(100)

  #   # Observer should see the message with Tony's address
  #   assert recv_message(server_client) == "bob: Please send payment to #{@tony_addr}"

  #   :gen_tcp.close(server_client)
  # end

  # test "case03 -- rewrites Boguscoin address in message from upstream", %{proxy_socket: client} do
  #   # Connect to real BudgetChat as another user
  #   {:ok, upstream_client} = connect(@budget_chat_port)
  #   assert recv_message(upstream_client) == "Welcome to budgetchat! What shall I call you?"
  #   send_message(upstream_client, "alice")
  #   _ = recv_message(upstream_client)

  #   # Alice sends a message with her Boguscoin address
  #   victim_addr = "7F1u3wSD5RbOHQmupo9nx4TnhQ"
  #   send_message(upstream_client, "Hi bob, send funds here: #{victim_addr}")

  #   :timer.sleep(100)

  #   # Close upstream client — not needed anymore
  #   :gen_tcp.close(upstream_client)

  #   # Back to proxy client (bob)
  #   assert recv_message(client) == "Welcome to budgetchat! What shall I call you?"
  #   send_message(client, "bob")
  #   _ = recv_message(client)

  #   # Now bob should receive alice's message — but rewritten
  #   expected = "alice: send funds here: #{@tony_addr}"

  #   assert recv_message(client) == expected,
  #          "Expected Bob to receive: '#{expected}', but got: '#{inspect(recv_message(client))}'"
  # end

  # test "case04 -- does not rewrite partial matches", %{proxy_socket: client} do
  #   assert recv_message(client) == "Welcome to budgetchat! What shall I call you?"
  #   send_message(client, "tester")
  #   _ = recv_message(client)

  #   # Send message with '7' not at word boundary
  #   send_message(client, "The code is x7ABC123 and should not be replaced")

  #   # Should not rewrite
  #   refute recv_message(client) =~ @tony_addr
  # end
end
