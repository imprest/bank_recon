defmodule BankRecon.DbaseParser do
  def parse(file, columns \\ [], map_fn \\ fn x -> x end) do
    data = File.read!(file)

    <<
      _version,
      _last_updated::3-bytes,
      rec_count::32-unsigned-little-integer,
      _header_size::16-unsigned-little-integer,
      a_rec_size::16-unsigned-little-integer,
      _::2-bytes,
      _incomplete_tx_flag,
      _encryption_flag,
      _multi_user_reserved::12-bytes,
      _mdx_flag,
      _lang_driver_id,
      _::2-bytes,
      rest::binary
    >> = data

    {fields, _field_count, rest} = parse_fields(rest)

    if columns === [] do
      parse_records(rest, fields, [], map_fn, a_rec_size - 1, rec_count, [])
    else
      parse_records(rest, fields, MapSet.new(columns), map_fn, a_rec_size - 1, rec_count, [])
    end
  end

  defp parse_records(_bin, _fields, _columns, _map_fn, _a_rec_size, 0, records) do
    :lists.reverse(records)
  end

  # TODO check if size of remaining bin > a_rec_size else stop processing since record is incomplete
  defp parse_records(bin, fields, columns, map_fn, a_rec_size, rec_count, records) do
    <<deleted::1-bytes, rec::binary-size(a_rec_size), rest::binary>> = bin

    if deleted === " " do
      case parse_record_by_fields(rec, fields, columns, %{}) |> map_fn.() do
        nil ->
          parse_records(rest, fields, columns, map_fn, a_rec_size, rec_count - 1, records)

        parsed_record ->
          parse_records(rest, fields, columns, map_fn, a_rec_size, rec_count - 1, [
            parsed_record | records
          ])
      end
    else
      parse_records(rest, fields, columns, map_fn, a_rec_size, rec_count - 1, records)
    end
  end

  defp parse_record_by_fields(_, [], _, acc), do: acc

  defp parse_record_by_fields(rec, fields, [], acc) do
    [field | f] = fields
    len = field.length
    <<data::binary-size(len), rest::binary>> = rec
    data = String.trim(data) |> parse_data(field.type, field.decimal_count)
    parse_record_by_fields(rest, f, [], Map.put(acc, field.name, data))
  end

  defp parse_record_by_fields(rec, fields, columns, acc) do
    [field | f] = fields
    len = field.length
    <<data::binary-size(len), rest::binary>> = rec

    case MapSet.member?(columns, field.name) do
      true ->
        data = String.trim(data) |> parse_data(field.type, field.decimal_count)
        parse_record_by_fields(rest, f, columns, Map.put(acc, field.name, data))

      false ->
        parse_record_by_fields(rest, f, columns, acc)
    end
  end

  defp parse_data(data, type, decimal_count) do
    case type do
      "C" ->
        data

      "N" ->
        if decimal_count === 0 do
          case data do
            "" ->
              0

            _ ->
              try do
                String.to_integer(data)
              rescue
                _ -> 0
              end
          end
        else
          case data do
            "" ->
              0.0

            _ ->
              try do
                String.to_float(data)
              rescue
                _ -> 0.0
              end
          end
        end

      "D" ->
        data

      "M" ->
        nil
    end
  end

  # There will always be 1 field/column for a table
  defp parse_fields(<<field_header::32-bytes, rest::binary>>),
    do: parse_fields([parse_field(field_header)], 1, rest)

  defp parse_fields(fields, count, bin) do
    <<stop::1-bytes, rest::binary>> = bin

    case stop === <<13>> do
      true ->
        <<zero::1-bytes, records::binary>> = rest

        case zero === <<0>> do
          true ->
            {:lists.reverse(fields), count, records}

          false ->
            {:lists.reverse(fields), count, rest}
        end

      false ->
        <<field_header::32-bytes, rest::binary>> = bin
        field = parse_field(field_header)
        parse_fields([field | fields], count + 1, rest)
    end
  end

  defp parse_field(
         <<name::11-bytes, type, _bytes_to_records::4-bytes, length::8-unsigned-little-integer,
           decimal_count::8-unsigned-little-integer, _::14-bytes>>
       ),
       do: %{
         name: parse_field_name(name),
         type: :binary.list_to_bin([type]),
         length: length,
         decimal_count: decimal_count
       }

  # Trim off null / zero bytes padding if any
  defp parse_field_name(bin), do: hd(:binary.split(bin, <<0>>))
end
