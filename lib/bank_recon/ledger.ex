defmodule BankRecon.Ledger do
  alias BankRecon.DbaseParser
  alias NimbleCSV.RFC4180, as: CSV

  @bank_csv_dir "/home/hvaria/Documents/Accounts/"
  @prog_dbf_dir "/home/hvaria/Documents/backup/"

  def test(code, year, month) do
    short_code = Calendar.strftime(Date.new!(year, month, 1), "%y%m")

    [data_cur_y, data_prev_y] = data_folder(year, month)

    folder =
      case code do
        "MB" -> "UMB"
        "EB" -> "Ecobank"
        "BB" -> "ABSA"
        "GB" -> "GT"
      end

    {bank, program} =
      [
        "#{@prog_dbf_dir}#{data_cur_y}/FIT#{short_code}.dbf"
      ]
      |> Enum.flat_map(fn x -> parse_dbf(x, code) end)
      |> combine_cash_splits(code)
      # |> Enum.sort_by(& &1.date, Date)
      |> Enum.into(%{}, fn x -> {x.id, x} end)
      |> compare_entries(
        bank_csv("#{@bank_csv_dir}#{folder}/20#{short_code}.csv", code),
        []
      )

    {cur, uncleared} = {rm_contras(bank), csv(Map.to_list(program))}
  end

  def run(code, year, month) do
    short_code = Calendar.strftime(Date.new!(year, month, 1), "%y%m")

    [data_cur_y, data_prev_y] = data_folder(year, month)

    folder =
      case code do
        "MB" -> "UMB"
        "EB" -> "Ecobank"
        "BB" -> "ABSA"
        "GB" -> "GT"
      end

    {bank, program} =
      [
        "#{@bank_csv_dir}#{data_cur_y}/FIT#{short_code}.dbf"
      ]
      |> Enum.flat_map(fn x -> parse_dbf(x, code) end)
      |> combine_cash_splits(code)
      # |> Enum.sort_by(& &1.date, Date)
      |> Enum.into(%{}, fn x -> {x.id, x} end)
      |> compare_entries(
        bank_csv("#{@bank_csv_dir}#{folder}/20#{short_code}.csv", code),
        []
      )

    prev_month =
      case month do
        1 -> Calendar.strftime(Date.new!(year - 1, 12, 1), "%y%m")
        _ -> Calendar.strftime(Date.new!(year, month - 1, 1), "%y%m")
      end

    {_, prev} =
      [
        "#{@bank_csv_dir}#{data_prev_y}/FIT#{prev_month}.dbf"
      ]
      |> Enum.flat_map(fn x -> parse_dbf(x, code) end)
      |> combine_cash_splits(code)
      # |> Enum.sort_by(& &1.date, Date)
      |> Enum.into(%{}, fn x -> {x.id, x} end)
      |> compare_entries(
        bank_csv("#{@bank_csv_dir}#{folder}/20#{prev_month}.csv", code),
        []
      )

    {cur, uncleared} = {rm_contras(bank), csv(Map.to_list(program))}
    # {cur, uncleared} = {rm_contras(bank), program}
    {compare_entries(prev, cur, []), uncleared}
    # {rm_contras(bank), csv(Map.to_list(program))}
    # {rm_contras(bank), program}
  end

  defp data_folder(year, month) do
    cur_y = String.slice(Integer.to_string(year), 2..3)
    prev_y = String.slice(Integer.to_string(year - 1), 2..3)

    case month do
      10 -> ["MGP#{cur_y}", "MGP#{prev_y}"]
      11 -> ["MGP#{cur_y}", "MGP#{cur_y}"]
      12 -> ["MGP#{cur_y}", "MGP#{cur_y}"]
      _ -> ["MGP#{prev_y}", "MGP#{prev_y}"]
    end
  end

  defp csv(map) do
    map
    |> Enum.into([], fn {_id, x} -> x end)
    |> Enum.sort_by(& &1.date, Date)
    |> Enum.map(fn x ->
      if x.drcr === "D" do
        [x.id, "#{x.desc} #{x.post_desc}", x.amount, ""]
      else
        [x.id, "#{x.desc} #{x.post_desc}", "", x.amount]
      end

      # IO.puts([
      #   Calendar.strftime(x.date, "%d-%m-%Y"),
      #   ",\"",
      #   x.ref,
      #   "\",\"",
      #   x.desc,
      #   "\",",
      #   Decimal.to_string(x.debit),
      #   ",",
      #   Decimal.to_string(x.credit)
      # ])
    end)
  end

  defp rm_contras(bank) do
    rm_contras(bank, [])
  end

  defp rm_contras([], acc), do: :lists.reverse(acc)

  defp rm_contras([h | t], acc) do
    [_, _, debit, credit] = h

    result =
      if debit === "" do
        find_contra(2, credit, t, false, [])
      else
        find_contra(3, debit, t, false, [])
      end

    case result do
      {true, new_list} -> rm_contras(new_list, acc)
      {false, _} -> rm_contras(t, [h | acc])
    end
  end

  defp find_contra(_position, _amount, [], false, acc), do: {false, :lists.reverse(acc)}

  defp find_contra(_position, _amount, _, true, acc), do: {true, acc}

  defp find_contra(position, amount, [h | t], found, acc) do
    if Enum.at(h, position) !== "" and Enum.at(h, position) === amount do
      find_contra(position, amount, t, true, :lists.reverse(acc) ++ t)
    else
      find_contra(position, amount, t, found, [h | acc])
    end
  end

  defp combine_cash_splits(p, "BB") do
    combine_cash_splits(p, "EB")
  end

  defp combine_cash_splits(p, "GB") do
    combine_cash_splits(p, "EB")
  end

  defp combine_cash_splits(p, "EB") do
    Enum.group_by(p, & &1.tx_code)
    |> Enum.map(fn {id, [h | t] = x} ->
      # only combine BR 'Bank Receipts like cash that was split into multiple entries'
      # so that it matches bank csv statement amounts
      if String.starts_with?(id, "BR R") or String.starts_with?(id, "BP P") do
        if length(x) !== 1 do
          Enum.reduce(t, h, fn y, acc -> %{acc | amount: acc.amount + y.amount} end)
        else
          h
        end
      else
        x
      end
    end)
    |> :lists.flatten()
  end

  defp combine_cash_splits(p, _) do
    Enum.group_by(p, & &1.tx_code)
    |> Enum.map(fn {id, [h | t] = x} ->
      # only combine BR 'Bank Receipts like cash that was split into multiple entries'
      # so that it matches bank csv statement amounts
      if String.starts_with?(id, "BR R") do
        if length(x) !== 1 do
          Enum.reduce(t, h, fn y, acc -> %{acc | amount: acc.amount + y.amount} end)
        else
          h
        end
      else
        x
      end
    end)
    |> :lists.flatten()
  end

  def compare_entries(program, [], result), do: {:lists.reverse(result), program}
  # take map of program entries like %{ id => {id, date, desc, debit, credit}, ...}
  # 2nd arg is list of entries like [[date, desc, debit, credit], ...]
  # Loop throught 2nd arg and remove matches entries from 1st arg, also dropping from 2nd arg
  # and not_found entries are pushed to result array
  def compare_entries(program, [h | t], result) do
    [date, _desc, debit, credit] = h

    if debit === "" do
      # Credit Entry
      temp =
        Enum.filter(program, fn {_id, m} ->
          m.drcr === "C" and m.amount === credit
        end)

      r =
        if length(temp) > 1 do
          Enum.sort_by(temp, fn {_id, m} -> m.date end, Date)
          |> hd

          # Enum.min_by(temp, fn {_id, m} -> Date.diff(date, m.date) end)
        else
          case temp do
            [] -> :not_found
            _ -> hd(temp)
          end
        end

      if r !== :not_found do
        {id, _} = r
        compare_entries(Map.delete(program, id), t, result)
      else
        compare_entries(program, t, [h | result])
      end
    else
      # Debit Entry
      r =
        Enum.find(program, :not_found, fn {_id, m} ->
          m.drcr === "D" and m.amount === debit and
            Date.compare(m.date, date) !== :gt
        end)

      if r !== :not_found do
        {id, _} = r
        compare_entries(Map.delete(program, id), t, result)
      else
        compare_entries(program, t, [h | result])
      end
    end
  end

  def bank_csv(file, code) do
    File.read!(file)
    |> CSV.parse_string(skip_headers: true)
    |> Enum.map(fn x ->
      case code do
        "MB" ->
          [date, desc, _value, debit, credit, _bal] = x
          [bank_date(date), String.slice(desc, 69, 40), debit, credit]

        "EB" ->
          [date, _value, _ref, desc, debit, credit, _bal] = x

          if String.starts_with?(credit, "-") do
            [
              bank_date(date),
              String.slice(desc, 0, 50),
              zero_to_empty(String.trim_leading(credit, "-")),
              zero_to_empty(debit)
            ]
          else
            [
              bank_date(date),
              String.slice(desc, 0, 50),
              zero_to_empty(debit),
              zero_to_empty(credit)
            ]
          end

        "BB" ->
          [date, _value, _ref, desc, _chq, debit, credit, _bal] = x

          [d, m, y] =
            date |> String.slice(0, 10) |> String.split("/") |> Enum.map(&String.to_integer(&1))

          [Date.new!(y, m, d), String.slice(desc, 0, 50), debit, credit]

        "GB" ->
          [date, _ref, _value, debit, credit, _bal, _, desc] = x
          [bank_date(date, "-"), desc, debit, credit]
      end
    end)
  end

  defp zero_to_empty("0"), do: ""
  defp zero_to_empty(string), do: string

  defp bank_date(date, split_on \\ " ") do
    [d, m, y] = String.split(date, split_on)

    if String.length(y) > 2 do
      Date.new!(String.to_integer(y), month_to_num(m), String.to_integer(d))
    else
      Date.new!(String.to_integer("20" <> y), month_to_num(m), String.to_integer(d))
    end
  end

  defp month_to_num(m) do
    case String.upcase(m) do
      "JAN" -> 1
      "FEB" -> 2
      "MAR" -> 3
      "APR" -> 4
      "MAY" -> 5
      "JUN" -> 6
      "JUL" -> 7
      "AUG" -> 8
      "SEP" -> 9
      "OCT" -> 10
      "NOV" -> 11
      "DEC" -> 12
    end
  end

  def parse_dbf(dbf, code) do
    DbaseParser.parse(
      dbf,
      [
        "TR_TYPE",
        "TR_CODE",
        "TR_NON",
        "TR_NOC",
        "TR_SRNO",
        "TR_DATE",
        "TR_GLCD",
        "TR_SLCD",
        "TR_DRCR",
        "TR_AMT",
        "TR_DESC",
        "TR_QTY"
      ],
      fn x ->
        if x["TR_CODE"] == code do
          %{
            id:
              x["TR_DATE"] <>
                " " <>
                x["TR_TYPE"] <>
                " " <>
                x["TR_NOC"] <>
                " " <> Integer.to_string(x["TR_NON"]) <> " " <> Integer.to_string(x["TR_SRNO"]),
            tx_code:
              x["TR_TYPE"] <>
                " " <>
                x["TR_NOC"] <>
                " " <> Integer.to_string(x["TR_NON"]),
            srno: x["TR_SRNO"],
            date: to_date(x["TR_DATE"]),
            desc: x["TR_QTY"],
            gl_code: x["TR_GLCD"],
            sl_code: x["TR_SLCD"],
            post_desc: clean_string(x["TR_DESC"]),
            drcr: x["TR_DRCR"],
            amount: x["TR_AMT"]
          }
        end
      end
    )
  end

  def parse_dbf_by_gl(dbf, code) do
    DbaseParser.parse(
      dbf,
      [
        "TR_TYPE",
        "TR_CODE",
        "TR_NON",
        "TR_NOC",
        "TR_SRNO",
        "TR_DATE",
        "TR_GLCD",
        "TR_SLCD",
        "TR_DRCR",
        "TR_AMT",
        "TR_DESC",
        "TR_QTY"
      ],
      fn x ->
        if x["TR_GLCD"] == code do
          %{
            id:
              x["TR_DATE"] <>
                " " <>
                x["TR_TYPE"] <>
                " " <>
                x["TR_NOC"] <>
                " " <> Integer.to_string(x["TR_NON"]) <> " " <> Integer.to_string(x["TR_SRNO"]),
            tx_code:
              x["TR_TYPE"] <>
                " " <>
                x["TR_NOC"] <>
                " " <> Integer.to_string(x["TR_NON"]),
            srno: x["TR_SRNO"],
            date: to_date(x["TR_DATE"]),
            desc: x["TR_QTY"],
            gl_code: x["TR_GLCD"],
            sl_code: x["TR_SLCD"],
            post_desc: clean_string(x["TR_DESC"]),
            drcr: x["TR_DRCR"],
            amount: x["TR_AMT"]
          }
        end
      end
    )
  end

  def print_to_console(x) do
    case x[:drcr] do
      "D" ->
        IO.puts(
          "#{x[:date]} \t #{String.pad_leading(Float.to_string(x[:amount]), 10)} \t\t\t #{x[:desc]} - #{x[:post_desc]}"
        )

      "C" ->
        IO.puts(
          "#{x[:date]} \t #{String.pad_leading(Float.to_string(x[:amount]), 22)} \t #{x[:desc]} - #{x[:post_desc]}"
        )
    end
  end

  @spec to_date(<<_::_*64>>) :: Date.t()
  def to_date(<<y0, y1, y2, y3, m0, m1, d0, d1>>),
    do: Date.from_iso8601!(<<y0, y1, y2, y3, "-", m0, m1, "-", d0, d1>>)

  @default_date Date.from_iso8601!("2016-10-01")
  def to_date(""), do: @default_date
  def to_date(nil), do: @default_date

  @spec clean_string(binary()) :: binary()
  def clean_string(bin) do
    case String.valid?(bin) do
      true ->
        bin

      false ->
        bin
        |> String.codepoints()
        |> Enum.filter(&String.valid?(&1))
        |> Enum.join()
    end
  end
end
