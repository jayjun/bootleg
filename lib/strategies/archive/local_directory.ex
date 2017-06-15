defmodule Bootleg.Strategies.Archive.LocalDirectory do
  @moduledoc """
  Stores builds on the local filesystem.

  Options:
  - `archive_directory`: path to build archive folder
  - `max_archives`: maximum number of archives to store before pruning

  Archives are named using the release version number, which by design must
  be parseable as an Elixir.Version. Archives are sorted by version with the
  oldest versions being those that are pruned first.
  """

  alias Bootleg.{Config, Config.ArchiveConfig, Project, UI}

  @file_extension ".tar.gz"
  @config_keys ~w(archive_directory max_archives)
  @file_reader Application.get_env(:bootleg, :file_reader, File)

  @doc """
  Archive the build filename passed to us
  """
  def archive(%Config{archive: %ArchiveConfig{archive_directory: directory, max_archives: max_archives} = config}, %Project{} = project, build_filename) do
    with :ok <- Bootleg.check_config(config, @config_keys),
         :ok <- check_directory(directory),
         :ok <- check_build(build_filename),
         {:ok, archive_path} <- copy_build(project.app_version, directory, build_filename),
         {:ok, builds} <- trim_builds(directory, max_archives) do

      archive_filename = Path.basename(archive_path)
      UI.debug "Build archives:"
      Enum.each(builds, fn(filename) ->
        out = case archive_filename == filename do
          true -> "--> "
          false -> "... "
        end
        UI.debug out <> String.trim_trailing(filename, @file_extension)
      end)

      UI.info "Archival complete: #{archive_path}"
      {:ok, archive_filename}
    else
      {:error, msg} -> raise "Error: #{msg}"
    end
  end

  @doc false
  def filter_sort_builds(files) do
    files
    |> Enum.filter(&valid_build_file/1)
    |> Enum.map(&String.trim_trailing(&1, @file_extension))
    |> Enum.sort(&sort_version/2)
    |> Enum.map(&(&1 <> @file_extension))
    |> Enum.reverse()
  end

  @doc false
  def valid_build_file(filename) do
    case String.ends_with?(filename, @file_extension) do
      true ->
        case Version.parse(String.trim_trailing(filename, @file_extension)) do
          {:ok, _} -> true
          :error -> false
        end
      false -> false
    end
  rescue
    Version.InvalidVersionError -> false
  end

  defp sort_version(a, b) do
    case Version.compare(a, b) do
      :gt -> true
      :eq -> true
      :lt -> false
    end
  end

  defp check_directory(directory) do
    with :ok <- @file_reader.mkdir_p(directory) do
      :ok
    else
      {:error, error} ->
        {:error, "Archive directory #{directory} couldn't be created: #{error}"}
    end
  end

  defp check_build(filename) do
    case @file_reader.exists?(filename) do
      true -> :ok
      false -> {:error, "Build file not found: #{filename}"}
    end
  end

  defp trim_builds(directory, limit) do
    builds =
      directory
      |> @file_reader.ls!
      |> filter_sort_builds
    num_builds = Enum.count(builds)

    if num_builds > limit do
      UI.info "Pruning old builds"
      old = Enum.take(builds, num_builds - limit)
      delete_files(directory, old)
      {:ok, builds -- old}
    else
      {:ok, builds}
    end
  end

  defp copy_build(version, directory, filename) do
    new_path = Path.join([directory, "#{version}#{@file_extension}"])
    UI.info "Storing build as #{version}#{@file_extension}"
    with :ok <- @file_reader.rename(filename, new_path) do
      {:ok, new_path}
    else
      {:error, error} ->
        {:error, "Error storing build as #{new_path}: #{error}"}
    end
  end

  defp delete_files(directory, old_files) do
    Enum.each(old_files, fn(filename) ->
      UI.debug("-x- " <> String.trim_trailing(filename, @file_extension))
      @file_reader.rm(Path.join(directory, filename))
    end)
  end
end