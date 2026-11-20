defmodule Taina.Ybira.Upload do
  @moduledoc """
  A durable request to ingest one staged file.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa
  alias Ypy.Ybira.File, as: YbiraFile

  @states [:completed, :failed, :processing, :queued]
  @error_codes [
    :blob_too_large,
    :folder_unavailable,
    :invalid_mime,
    :owner_inactive,
    :processing_failed,
    :staging_invalid,
    :staging_missing,
    :storage_quota_exceeded,
    :upload_conflict
  ]

  @type error_code ::
          :blob_too_large
          | :folder_unavailable
          | :invalid_mime
          | :owner_inactive
          | :processing_failed
          | :staging_invalid
          | :staging_missing
          | :storage_quota_exceeded
          | :upload_conflict
  @type state :: :completed | :failed | :processing | :queued

  schema "ybira_uploads" do
    belongs_to :dono, Ava
    field :error_code, Ecto.Enum, values: @error_codes
    belongs_to :file, YbiraFile
    field :filename, :string
    field :folder_rkey, :string
    field :oban_job_id, :integer
    field :public_id, :string
    field :relative_path, :string
    field :size, :integer
    field :staging_key, :string
    field :state, Ecto.Enum, values: @states, default: :queued
    belongs_to :tekoa, Tekoa

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          dono_id: integer() | nil,
          error_code: error_code() | nil,
          file_id: integer() | nil,
          filename: String.t() | nil,
          folder_rkey: String.t() | nil,
          oban_job_id: integer() | nil,
          public_id: String.t() | nil,
          relative_path: String.t() | nil,
          size: non_neg_integer() | nil,
          staging_key: String.t() | nil,
          state: state(),
          tekoa_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc "Validates fields used to create or transition an upload."
  def changeset(upload, attrs) do
    upload
    |> cast(attrs, [
      :error_code,
      :file_id,
      :filename,
      :folder_rkey,
      :oban_job_id,
      :public_id,
      :relative_path,
      :size,
      :staging_key,
      :state
    ])
    |> validate_required([
      :dono_id,
      :filename,
      :public_id,
      :size,
      :staging_key,
      :state,
      :tekoa_id
    ])
    |> validate_length(:filename, min: 1, max: 255)
    |> validate_number(:size, greater_than: 0)
    |> check_constraint(:size, name: :ybira_uploads_size_positive)
    |> foreign_key_constraint(:tekoa_id)
    |> foreign_key_constraint(:dono_id)
    |> foreign_key_constraint(:file_id)
    |> unique_constraint(:public_id)
    |> unique_constraint(:file_id)
  end
end
