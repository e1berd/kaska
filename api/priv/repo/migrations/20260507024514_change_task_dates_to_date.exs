defmodule Kaska.Repo.Migrations.ChangeTaskDatesToDate do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE tasks
      ALTER COLUMN start_date TYPE date USING start_date::date,
      ALTER COLUMN end_date   TYPE date USING end_date::date
    """
  end

  def down do
    execute """
    ALTER TABLE tasks
      ALTER COLUMN start_date TYPE timestamp USING start_date::timestamp,
      ALTER COLUMN end_date   TYPE timestamp USING end_date::timestamp
    """
  end
end
