defmodule Protohacker.BudgetChatTest do
  use ExUnit.Case

  # localhost
  @host {127, 0, 0, 1}
  @port 3007
  @connect_timeout 500
  @recv_timeout 500
  @welcome_message "Welcome to budgetchat! What shall I call you?"

  defp connect_client do
    {:ok, socket} =
      :gen_tcp.connect(@host, @port, [:binary, packet: :line, active: false], @connect_timeout)

    socket
  end

  defp recv(socket, timeout \\ @recv_timeout) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} -> String.trim_trailing(data, "\n")
      other -> other
    end
  end

  defp send_msg(socket, text) do
    :gen_tcp.send(socket, text <> "\n")
  end

  defp close(socket) do
    :gen_tcp.close(socket)
  end

  test "case01 -- budget-chat: full interaction" do
    # Connect Alice
    alice = connect_client()
    assert recv(alice) =~ @welcome_message

    # Set name
    send_msg(alice, "alice")

    # Should get list of others (none yet)
    assert recv(alice) =~ "* The room contains:"

    # Connect Bob
    bob = connect_client()
    assert recv(bob) =~ @welcome_message
    send_msg(bob, "bob")
    bob_users = recv(bob)
    assert bob_users =~ "* The room contains:"
    assert bob_users =~ "alice"

    # Alice should see Bob join
    assert recv(alice) =~ "* bob has entered the room"

    # Alice sends a message
    send_msg(alice, "Hello, world!")

    # Bob should receive it
    assert recv(bob) == "[alice] Hello, world!"

    # Bob replies
    send_msg(bob, "hi alice")
    assert recv(alice) == "[bob] hi alice"

    # Connect Charlie with invalid name (non-alphanumeric)
    charlie = connect_client()
    assert recv(charlie) =~ @welcome_message
    send_msg(charlie, "charlie!")
    # Should be disconnected immediately, no further messages
    assert :gen_tcp.recv(charlie, 0, 100) == {:error, :closed}

    # Invalid name should not notify others
    send_msg(alice, "anyone there?")
    assert recv(bob) == "[alice] anyone there?"

    # Now connect valid Charlie
    charlie = connect_client()
    assert recv(charlie) =~ @welcome_message
    send_msg(charlie, "charlie")
    assert recv(charlie) =~ "* The room contains:"
    assert recv(charlie) =~ "alice"
    assert recv(charlie) =~ "bob"

    # Others should see Charlie join
    assert recv(alice) =~ "* charlie has entered the room"
    assert recv(bob) =~ "* charlie has entered the room"

    # Charlie sends message
    send_msg(charlie, "I'm here!")
    assert recv(alice) == "[charlie] I'm here!"
    assert recv(bob) == "[charlie] I'm here!"

    # Bob disconnects
    close(bob)

    # Alice and Charlie should see he left
    assert recv(alice) =~ "* bob has left the room"
    assert recv(charlie) =~ "* bob has left the room"

    # Alice sends after Bob left
    send_msg(alice, "Bye bob")
    assert recv(charlie) == "[alice] Bye bob"

    # Clean up
    close(alice)
    close(charlie)
  end

  test "rejects duplicate name and disconnects client" do
    alice1 = connect_client()
    assert recv(alice1) =~ @welcome_message
    send_msg(alice1, "alice")

    # Join second alice
    alice2 = connect_client()
    assert recv(alice2) =~ @welcome_message
    send_msg(alice2, "alice")

    # Should be rejected and disconnected
    assert :gen_tcp.recv(alice2, 0, 100) == {:error, :closed}

    # Original alice should NOT see any join/leave
    assert :gen_tcp.recv(alice1.socket, 0, 100) == {:error, :timeout} || {:error, :closed}
  end

  test "does not broadcast leave message when unregistered client disconnects" do
    client = connect_client()
    assert recv(client) =~ @welcome_message

    # Disconnect without setting name
    close(client)

    # No "* ... has left" should be sent
    # Try to connect another client — should not receive any ghost leave message
    alice = connect_client()
    assert recv(alice) =~ @welcome_message
    send_msg(alice, "alice")
    assert recv(alice) =~ "* The room contains:"

    # No unexpected messages
    refute recv(alice, 100) =~ "has left the room"
    close(alice)
  end

  test "chat messages are not echoed back to sender" do
    alice = connect_client()
    assert recv(alice) =~ @welcome_message
    send_msg(alice, "alice")

    bob = connect_client()
    assert recv(bob) =~ @welcome_message
    send_msg(bob, "bob")
    assert recv(bob) =~ "alice"
    assert recv(alice) =~ "* bob has entered the room"

    send_msg(alice, "Hello bob")

    # Alice should not receive her own message
    assert :gen_tcp.recv(alice.socket, 0, 100) == {:error, :timeout}

    # Bob should receive it
    assert recv(bob) == "[alice] Hello bob"

    close(alice)
    close(bob)
  end
end
