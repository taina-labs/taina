defmodule Taina.Config do
  @moduledoc "Strict, typed configuration loaded from `taina.conf`."

  @behaviour Config.Provider

  @default_max_blob_size 2 * 1024 * 1024 * 1024
  @default_max_concurrent_uploads 10
  @max_integer 9_223_372_036_854_775_807

  defstruct url_scheme: :https,
            hostname: nil,
            url_port: nil,
            bind_ip: {0, 0, 0, 0},
            port: 4000,
            max_blob_size: @default_max_blob_size,
            max_concurrent_uploads: @default_max_concurrent_uploads,
            data_dir: "/app/data",
            storage_dir: "/app/storage",
            backup_dir: "/app/backups",
            backup_enabled: true,
            update_check: false,
            secret_key_base_file: nil

  @keys ~w(
    url_scheme
    hostname
    url_port
    bind_ip
    port
    max_blob_size
    max_concurrent_uploads
    data_dir
    storage_dir
    backup_dir
    backup_enabled
    update_check
    secret_key_base_file
  )
  @template """
  # Public URL, after TLS termination.
  url_scheme = https
  hostname = community.example.org
  url_port = 443

  # HTTP listener inside the container.
  bind_ip = 0.0.0.0
  port = 4000

  # Upload limits.
  max_blob_size = 2147483648
  max_concurrent_uploads = 10

  # Persistent application paths.
  data_dir = /app/data
  storage_dir = /app/storage
  backup_dir = /app/backups

  backup_enabled = true
  update_check = false

  # Optional. Defaults to DATA_DIR/secret_key_base.
  # secret_key_base_file = /app/data/secret_key_base
  """

  @impl true
  def init(opts), do: opts

  @impl true
  def load(config, {:system, name}) do
    settings = effective!(path(name))
    Config.Reader.merge(config, taina: application_config(settings))
  end

  def path do
    path("TAINA_CONFIG")
  end

  def template, do: @template

  @doc "O limite configurado por arquivo, em bytes."
  @spec max_blob_size() :: pos_integer()
  def max_blob_size do
    :taina
    |> Application.get_env(:upload, [])
    |> Keyword.get(:max_blob_size, @default_max_blob_size)
  end

  @doc "A quantidade de arquivos que uma tela pode enviar em paralelo."
  @spec max_concurrent_uploads() :: pos_integer()
  def max_concurrent_uploads do
    :taina
    |> Application.get_env(:upload, [])
    |> Keyword.get(:max_concurrent_uploads, @default_max_concurrent_uploads)
  end

  def effective(path \\ path()) do
    with {:ok, text} <- File.read(path),
         {:ok, entries} <- parse(text),
         {:ok, settings} <- resolve(entries) do
      {:ok, settings}
    else
      {:error, :enoent} -> {:error, {:missing_file, path}}
      {:error, reason} -> {:error, {:invalid, path, reason}}
    end
  end

  def effective!(path \\ path()) do
    case effective(path) do
      {:ok, settings} -> settings
      {:error, reason} -> raise ArgumentError, describe(reason)
    end
  end

  def parse(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {line, number}, {:ok, entries} ->
      case parse_line(line) do
        :skip -> {:cont, {:ok, entries}}
        {:ok, key, value} when key in @keys -> add_entry(key, value, number, entries)
        {:ok, key, _value} -> {:halt, {:error, {:unknown_key, key, number}}}
        {:error, reason} -> {:halt, {:error, {reason, number}}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Map.new(entries, fn {key, value, line} -> {key, {value, line}} end)}
      error -> error
    end
  end

  defp add_entry(key, value, line, entries) do
    if Map.has_key?(Map.new(entries, fn {key, value, _line} -> {key, value} end), key) do
      {:halt, {:error, {:duplicate_key, key, line}}}
    else
      {:cont, {:ok, [{key, value, line} | entries]}}
    end
  end

  defp resolve(file) do
    scheme = fetch(file, "url_scheme", "https")

    defaults = %{
      "url_port" => {if(scheme == "http", do: "80", else: "443"), nil},
      "max_blob_size" => {to_string(@default_max_blob_size), nil},
      "max_concurrent_uploads" => {to_string(@default_max_concurrent_uploads), nil}
    }

    values = Map.merge(defaults, file)

    with {:ok, url_scheme} <- enum(values, "url_scheme", ~w(http https)),
         {:ok, hostname} <- required(values, "hostname"),
         {:ok, url_port} <- integer(values, "url_port", 1, 65_535),
         {:ok, bind_ip} <- ip(values, "bind_ip", "0.0.0.0"),
         {:ok, port} <- integer(values, "port", 1, 65_535),
         {:ok, max_blob_size} <- integer(values, "max_blob_size", 1, @max_integer),
         {:ok, max_concurrent_uploads} <- integer(values, "max_concurrent_uploads", 1, 1_000),
         {:ok, data_dir} <- required(values, "data_dir"),
         {:ok, storage_dir} <- required(values, "storage_dir"),
         {:ok, backup_dir} <- required(values, "backup_dir"),
         {:ok, backup_enabled} <- boolean(values, "backup_enabled", true),
         {:ok, update_check} <- boolean(values, "update_check", false) do
      {:ok,
       %__MODULE__{
         url_scheme: String.to_existing_atom(url_scheme),
         hostname: hostname,
         url_port: url_port,
         bind_ip: bind_ip,
         port: port,
         max_blob_size: max_blob_size,
         max_concurrent_uploads: max_concurrent_uploads,
         data_dir: data_dir,
         storage_dir: storage_dir,
         backup_dir: backup_dir,
         backup_enabled: backup_enabled,
         update_check: update_check,
         secret_key_base_file: value(values, "secret_key_base_file")
       }}
    end
  end

  defp required(values, key) do
    case value(values, key) do
      current when current in [nil, ""] -> {:error, invalid_value(values, key)}
      current -> {:ok, current}
    end
  end

  defp enum(values, key, allowed) do
    current = value(values, key)
    if current in allowed, do: {:ok, current}, else: {:error, invalid_value(values, key)}
  end

  defp integer(values, key, min, max) do
    case Integer.parse(value(values, key, "")) do
      {value, ""} when value >= min and value <= max -> {:ok, value}
      _ -> {:error, invalid_value(values, key)}
    end
  end

  defp boolean(values, key, default) do
    case value(values, key, to_string(default)) do
      value when value in ["true", "1"] -> {:ok, true}
      value when value in ["false", "0"] -> {:ok, false}
      _ -> {:error, invalid_value(values, key)}
    end
  end

  defp ip(values, key, default) do
    value = value(values, key, default)

    case :inet.parse_address(String.to_charlist(value)) do
      {:ok, address} -> {:ok, address}
      _ -> {:error, invalid_value(values, key)}
    end
  end

  defp fetch(values, key, default), do: value(values, key, default)

  defp value(values, key, default \\ nil) do
    case Map.get(values, key) do
      {current, _line} -> current
      nil -> default
    end
  end

  defp invalid_value(values, key) do
    case Map.get(values, key) do
      {_value, line} when is_integer(line) -> {:invalid_value, key, line}
      _ -> {:invalid_value, key}
    end
  end

  defp application_config(settings) do
    secret = secret(settings.secret_key_base_file || Path.join(settings.data_dir, "secret_key_base"))

    [
      {Taina.Repo, [database: Path.join(settings.data_dir, "taina.db"), default_transaction_mode: :immediate]},
      {TainaWeb.Endpoint,
       [
         url: [host: settings.hostname, port: settings.url_port, scheme: Atom.to_string(settings.url_scheme)],
         http: [ip: settings.bind_ip, port: settings.port],
         secret_key_base: secret,
         check_origin: false
       ]},
      storage_root: settings.storage_dir,
      upload: [
        max_blob_size: settings.max_blob_size,
        max_concurrent_uploads: settings.max_concurrent_uploads
      ],
      backup: [enabled: settings.backup_enabled, dir: settings.backup_dir],
      update_check: [enabled: settings.update_check],
      data_dir: settings.data_dir,
      config: settings
    ]
  end

  defp secret(path), do: if(File.regular?(path), do: String.trim(File.read!(path)))

  defp path(name) do
    case System.get_env(name) do
      nil -> "taina.conf"
      "" -> "taina.conf"
      value -> value
    end
  end

  defp parse_line(line) do
    [before | _] = String.split(line, "#", parts: 2)

    case String.split(before, "=", parts: 2) do
      [key, value] ->
        build_line(String.trim(key), String.trim(value))

      [value] ->
        if String.trim(value) == "", do: :skip, else: {:error, :invalid_line}

      _ ->
        {:error, :missing_value}
    end
  end

  defp build_line("", _value), do: {:error, :invalid_line}
  defp build_line(_key, ""), do: {:error, :missing_value}
  defp build_line(key, value), do: {:ok, key, value}

  def describe({:missing_file, path}), do: "config file #{path} does not exist"
  def describe({:invalid, path, reason}), do: "config file #{path} is invalid: #{describe(reason)}"
  def describe({:unknown_key, key, line}), do: "unknown key #{inspect(key)} on line #{line}"
  def describe({:duplicate_key, key, line}), do: "duplicate key #{inspect(key)} on line #{line}"
  def describe({reason, line}) when is_integer(line), do: "#{inspect(reason)} on line #{line}"
  def describe({:invalid_value, key}), do: "invalid value for #{key}"
  def describe({:invalid_value, key, line}), do: "invalid value for #{key} on line #{line}"
  def describe(reason), do: inspect(reason)
end
