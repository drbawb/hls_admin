defmodule HlsAdminWeb.Output do
  use Phoenix.HTML

  @doc "Takes an atom and converts it to a status line."
  def print_status(status) do
    status_string = Atom.to_string(status)
    status_title  = String.capitalize(status_string)

    line_class = 
      ["status-line", status_string]
      |> Enum.join(" ")

    content_tag :div, class: line_class do
      content_tag :span, do: status_title
    end
  end
end
