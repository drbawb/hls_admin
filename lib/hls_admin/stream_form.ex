defmodule HlsAdmin.StreamForm do
  alias Ecto.Changeset
  require Logger
  use Ecto.Schema


  schema "stream_forms" do
    field :av_path, :string
    field :st_path, :string

    field :idx_a, :string
    field :idx_v, :string
    field :idx_s, :string
  end

  def changeset(stream_form, params \\ %{}) do
    stream_form
    |> Changeset.cast(params, [:av_path, :st_path, :idx_a, :idx_v, :idx_s])
    |> Changeset.validate_required([:av_path, :idx_a, :idx_v])
    |> validate_subtitle_path()
  end

  defp validate_subtitle_path(changeset) do
    has_st_path = Map.has_key?(changeset.changes, :st_path)
    value = Changeset.get_field(changeset, :idx_s)
    has_missing_value = is_nil(value) or value == ""

    case {has_st_path, has_missing_value} do
      {true, true} ->
        [idx_s: {"must be set if st path present", [validation: :subtitle_path]}]

      {_, _} -> []
    end

    changeset
    # is_valid = Enum.count(new_errors) <= 0
    # %{changeset | errors: changeset.errors ++ new_errors, valid?: (changeset.valid? and is_valid)}
  end
end
