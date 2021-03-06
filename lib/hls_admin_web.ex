defmodule HlsAdminWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, views, channels and so on.

  This can be used in your application as:

      use HlsAdminWeb, :controller
      use HlsAdminWeb, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define any helper function in modules
  and import those modules here.
  """

  def controller do
    quote do
      use Phoenix.Controller, namespace: HlsAdminWeb

      import Plug.Conn
      import HlsAdminWeb.Gettext
      import Phoenix.LiveView.Controller
      alias HlsAdminWeb.Router.Helpers, as: Routes
    end
  end

  def live_view do 
    quote do
      use Phoenix.LiveView,
        layout: {HlsAdminWeb.LayoutView, "live.html"}

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 1, get_flash: 2, view_module: 1]

      # Import convenience functions from live_view
      import Phoenix.LiveView.Helpers


      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML

      import HlsAdminWeb.ErrorHelpers
      import HlsAdminWeb.Gettext
      import HlsAdminWeb.Output
      alias HlsAdminWeb.Router.Helpers, as: Routes
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 1, get_flash: 2, view_module: 1]

      # Import convenience functions from live_view
      import Phoenix.LiveView.Helpers


      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML

      import HlsAdminWeb.ErrorHelpers
      import HlsAdminWeb.Gettext
      import HlsAdminWeb.Output
      alias HlsAdminWeb.Router.Helpers, as: Routes
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/hls_admin_web/templates",
        namespace: HlsAdminWeb

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 1, get_flash: 2, view_module: 1]

      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML

      import HlsAdminWeb.ErrorHelpers
      import HlsAdminWeb.Gettext
      import HlsAdminWeb.Output
      alias HlsAdminWeb.Router.Helpers, as: Routes
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      import HlsAdminWeb.Gettext
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
