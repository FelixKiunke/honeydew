if Code.ensure_loaded?(Ecto) do
  defmodule Honeydew.EctoSource.SQL.SQLite3 do
    @moduledoc false

    alias Honeydew.EctoSource
    alias Honeydew.EctoSource.SQL
    alias Honeydew.EctoSource.State

    @behaviour SQL

    @impl true
    def integer_type do
      :integer
    end

    @impl true
    def table_name(schema) do
      schema.__schema__(:source)
    end

    @impl true
    def ready do
      timestamp(SQL.far_in_the_past())
      |> time_in_msecs
      |> msecs_ago
    end

    @impl true
    def delay_ready(state) do
      "UPDATE #{state.table}
      SET #{state.lock_field} = (#{ready()} + $1 * 1000),
          #{state.private_field} = $2
      WHERE #{SQL.where_keys_fragment(state, 3)}"
    end

    @impl true
    def reserve(state) do
      key_list_fragment = Enum.join(state.key_fields, ", ")
      returning_fragment = [state.private_field | state.key_fields] |> Enum.join(", ")

      "UPDATE #{state.table}
      SET #{state.lock_field} = #{reserve_at(state)}
      WHERE (#{key_list_fragment}) = (
        SELECT #{key_list_fragment}
        FROM #{state.table}
        WHERE #{state.lock_field} BETWEEN 0 AND #{ready()} #{run_if(state)}
        ORDER BY #{state.lock_field}
        LIMIT 1
      )
      RETURNING #{returning_fragment}"
    end

    defp run_if(%State{run_if: nil}), do: nil
    defp run_if(%State{run_if: run_if}), do: "AND (#{run_if})"

    @impl true
    def cancel(state) do
      "UPDATE #{state.table}
      SET #{state.lock_field} = NULL
      WHERE
        #{SQL.where_keys_fragment(state, 1)}
      RETURNING #{state.lock_field}"
    end


    @impl true
    def status(state) do
      "SELECT COUNT(IF(#{state.lock_field} IS NOT NULL, 1, NULL)) AS count,

              COUNT(IF(#{state.lock_field} = #{EctoSource.abandoned()}, 1, NULL)) AS abandoned,

              COUNT(IF(
                0 <= #{state.lock_field} AND #{state.lock_field} <= #{ready()},
              1, NULL)) AS ready,

              COUNT(IF(
                #{ready()} < #{state.lock_field} AND #{state.lock_field} < #{stale_at()},
              1, NULL)) AS delayed,

              COUNT(IF(
                #{stale_at()} < #{state.lock_field} AND #{state.lock_field} < #{now()},
              1, NULL)) AS stale,

              COUNT(IF(
                #{now()} < #{state.lock_field} AND #{state.lock_field} <= #{reserve_at(state)},
              1, NULL)) AS in_progress
      FROM #{state.table}"
    end

    @impl true
    def filter(state, :abandoned) do
      keys_fragment = Enum.join(state.key_fields, ", ")
      "SELECT #{keys_fragment} FROM #{state.table} WHERE #{state.lock_field} = #{EctoSource.abandoned()}"
    end

    @impl true
    def reset_stale(state) do
      "UPDATE #{state.table}
       SET #{state.lock_field} = #{ready()},
           #{state.private_field} = NULL
       WHERE
         #{stale_at()} < #{state.lock_field}
         AND
         #{state.lock_field} < #{now()}"
    end

    defp reserve_at(state) do
      "#{now()} + #{state.stale_timeout}"
    end

    defp stale_at do
      time_in_msecs(timestamp("now", "-5 years"))
    end

    defp msecs_ago(msecs) do
      "(#{now()} - #{msecs})"
    end

    defp now do
      time_in_msecs(timestamp("now"))
    end

    defp timestamp(time, mod \\ nil) do
      "((julianday('#{time}'#{if mod do ", '#{mod}'" end})-2440587.5)*86400.0)"
    end

    defp time_in_msecs(time) do
      "round(#{time} * 1000)"
    end
  end
end
