defmodule HlsAdmin.AdminUI do
  use GenServer
  require Logger

  @moduledoc """
  # Admin File Browser UI Server

  This server implements an in-memory file browser which operates
  locally on the current node. It is initialized w/ a `parent_path`
  which serves to root the browser in the filesystem tree. 

  Traversing the tree requires pushing/popping relative segments
  of a path: representing a child directory somewhere under the
  parent path.
  """
  
  @initial_config %{parent_path: "/mnt/media", path_segments: []}

  def init(_state) do
    {:ok, @initial_config}
  end

  defp util_relative_dir(state) do
    state.path_segments
    |> List.foldl("", fn (el,acc) -> Path.join(acc, el) end)
  end

  defp util_absolute_dir(state) do
    base_dir  = state.parent_path
    child_dir = util_relative_dir(state)
    Path.join(base_dir, child_dir)
  end

  # cwd: retrieve the current working directory
  def handle_call(:cwd, _from, state) do
    {:reply, {:ok, util_absolute_dir(state)}, state}
  end

  # enumerate: list the contents of the current file browser directory
  def handle_call(:enumerate, _from, state) do
    absolute_dir = util_absolute_dir(state)

    {:ok, ents} = File.ls(absolute_dir)
    ents = ents
           |> Enum.sort(&(&1 <= &2))
           |> Enum.map(fn ent ->
             %{
               rel: ent,
               abs: Path.join(absolute_dir, ent),
             }
           end)
           |> Enum.map(&enumerate_ty_tuple(&1))


    {:reply, {:ok, ents}, state}
  end

  def handle_call(:pop, _from, state) do
    new_segments = case Enum.reverse(state.path_segments) do
      [head | tail] -> Enum.reverse(tail)
      [] -> []
    end

    {:reply, :ok, %{state | path_segments: new_segments}}
  end

  def handle_call({:push, dir}, _from, state) when is_binary(dir) do
    Logger.debug "pushing #{dir} ..."

    with {:ok, legal_target}    <- validate_dir_legal(dir),
         {:ok, existing_target} <- validate_dir_exists(state, legal_target)
    do
      Logger.debug "existing target: #{inspect existing_target}"
      {:reply, :ok, %{state | path_segments: existing_target}}
    else
      err -> {:reply, err, state}
    end
  end

  def handle_call({:push, _dir}, _from, state) do
    {:reply, {:error, :push_check_path_type}, state}
  end


  defp validate_dir_exists(state, dir) do
    rel_path = state.path_segments
               |> List.foldl("", fn (el,acc) -> Path.join(acc, el) end)

    cwd = Path.join(state.parent_path, rel_path)
    nwd = Path.join(cwd, dir)

    cond do
      File.exists?(nwd) and File.dir?(nwd) ->
        {:ok, state.path_segments ++ [dir]}

      File.exists?(nwd) ->
        {:error, :push_target_not_dir}

      true ->
        {:error, :push_target_not_exists}
    end
  end

  defp validate_dir_legal(path) do
    if path == "." or path == ".." do
      {:error, :push_relative_path_disallowed}
    else
      {:ok, path}
    end
  end

  defp enumerate_ty_tuple(path) do
    if File.dir?(path.abs) do
      {:dir, path.rel}
    else
      {:file, path.rel}
    end
  end

end
