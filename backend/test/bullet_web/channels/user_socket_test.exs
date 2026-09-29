defmodule BulletWeb.UserSocketTest do
  use BulletWeb.ChannelCase, async: true

  import Bullet.AccountsFixtures

  alias Bullet.Accounts
  alias BulletWeb.{AccessToken, UserSocket}

  setup do
    %{user: user, device: device} = session_fixture()
    %{user: user, device: device, token: AccessToken.sign(user.id, device.id)}
  end

  test "connects with a valid token and joins only its own user topic", %{
    user: user,
    token: token
  } do
    assert {:ok, socket} = connect(UserSocket, %{}, connect_info: %{auth_token: token})
    assert {:ok, _, _} = subscribe_and_join(socket, "user:#{user.id}", %{})

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(socket, "user:#{UUIDv7.generate()}", %{})
  end

  test "refuses missing or forged tokens" do
    assert :error = connect(UserSocket, %{}, connect_info: %{})
    assert :error = connect(UserSocket, %{}, connect_info: %{auth_token: "forged"})
  end

  test "revoking the device broadcasts disconnect to its socket id", %{
    user: user,
    device: device,
    token: token
  } do
    {:ok, socket} = connect(UserSocket, %{}, connect_info: %{auth_token: token})
    assert UserSocket.id(socket) == "device_socket:#{device.id}"

    BulletWeb.Endpoint.subscribe(UserSocket.id(socket))
    :ok = Accounts.revoke_device(user, device.id)
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

    assert :error = connect(UserSocket, %{}, connect_info: %{auth_token: token})
  end
end
