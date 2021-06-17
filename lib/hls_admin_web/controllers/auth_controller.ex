defmodule HlsAdminWeb.AuthController do
  use HlsAdminWeb, :controller

  def index(conn, _params) do
    user_role = get_session(conn, :auth_role)

    case user_role do
      :admin -> redirect_admin_view(conn)
      _role  -> redirect_login_page(conn)
    end
  end

  def new(conn, _params) do
    render(conn, "new.html")
  end

  def create(conn, %{"username" => username, "password" => password}) do
    login_map = Application.get_env(:hls_admin, :logins, %{})
    login_pwd_hash = Map.get(login_map, username)

    if not is_nil(login_pwd_hash) and Argon2.verify_pass(password, login_pwd_hash) do
      conn
      |> put_session(:auth_role, :admin)
      |> redirect(to: Routes.auth_path(conn, :index))
    else
      conn
      |> put_flash(:error, "Login incorrect")
      |> redirect(to: Routes.auth_path(conn, :new))
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session(:auth_role)
    |> redirect(to: Routes.auth_path(conn, :index))
  end

  defp redirect_admin_view(conn) do
    conn
    |> live_render(HlsAdminWeb.AdminView)
  end

  defp redirect_login_page(conn) do
    conn
    |> redirect(to: Routes.auth_path(conn, :new))
  end
end
