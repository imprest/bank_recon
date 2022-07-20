defmodule BankRecon do
  import Bitwise
  import :wx_const

  require Record
  Record.defrecordp(:wx, Record.extract(:wx, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxClose, Record.extract(:wxClose, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxSize, Record.extract(:wxSize, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxCommand, Record.extract(:wxCommand, from_lib: "wx/include/wx.hrl"))

  Record.defrecordp(
    :wxFileDirPicker,
    Record.extract(:wxFileDirPicker, from_lib: "wx/include/wx.hrl")
  )

  @behaviour :wx_object

  @title "Bank Reconciler"
  @file_picker 1
  @btn_calc 2
  @text_result 3

  @moduledoc """
  Documentation for `BankRecon`.
  """

  @doc """
  Start BankRecon gui

  ## Examples

      iex> BankRecon.start_link()
      {:wx_ref, 35, :wxFrame, _pid}

  """
  def start_link() do
    :wx_object.start_link(__MODULE__, [], [])
  end

  def init(_args \\ []) do
    :wx.new()
    frame = :wxFrame.new(:wx.null(), wxID_ANY(), @title)
    :wxFrame.center(frame)
    :wxFrame.connect(frame, :size)
    :wxFrame.connect(frame, :close_window)
    status_bar = :wxFrame.createStatusBar(frame)

    panel = :wxPanel.new(frame)

    main_sizer = :wxBoxSizer.new(wxVERTICAL())
    top_sizer = :wxStaticBoxSizer.new(wxVERTICAL(), panel, label: "Select CSV File:")

    file_picker = :wxFilePickerCtrl.new(panel, @file_picker)
    :wxFilePickerCtrl.connect(file_picker, :command_filepicker_changed)

    btn_calc = :wxButton.new(panel, @btn_calc, label: "&Reconcile")
    :wxButton.connect(btn_calc, :command_button_clicked, userData: "&Reconcile")
    :wxButton.disable(btn_calc)

    text_result =
      :wxTextCtrl.new(panel, @text_result,
        size: {380, 450},
        style: wxDEFAULT() ||| wxTE_MULTILINE() ||| wxEXPAND()
      )

    :wxSizer.add(top_sizer, file_picker, border: 5, flag: wxALL() ||| wxEXPAND())
    :wxSizer.add(top_sizer, btn_calc, border: 5, flag: wxALL() ||| wxEXPAND())

    :wxSizer.add(main_sizer, top_sizer, border: 10, flag: wxALL() ||| wxEXPAND())

    :wxSizer.add(main_sizer, text_result,
      border: 10,
      proportion: 4,
      flag: wxLEFT() ||| wxRIGHT() ||| wxBOTTOM() ||| wxEXPAND()
    )

    :wxPanel.setSizer(panel, main_sizer)
    :wxSizer.fit(main_sizer, panel)

    :wxFrame.fit(frame)
    :wxFrame.show(frame)

    state = %{
      panel: panel,
      file_path: "",
      btn_calc: btn_calc,
      text_result: text_result,
      status_bar: status_bar
    }

    {frame, state}
  end

  def handle_event(wx(event: wxSize(size: size)), state = %{panel: panel}) do
    :wxPanel.setSize(panel, size)
    {:noreply, state}
  end

  def handle_event(wx(event: wxClose()), state), do: {:stop, :normal, state}

  def handle_event(
        wx(event: wxFileDirPicker(type: :command_filepicker_changed, path: path)),
        state = %{btn_calc: btn_calc}
      ) do
    if Path.extname(path) === ".csv" do
      :wxButton.enable(btn_calc)
    else
      :wxButton.disable(btn_calc)
    end

    {:noreply, %{state | file_path: path}}
  end

  def handle_event(
        wx(id: @btn_calc, event: wxCommand()),
        state = %{text_result: text_result, file_path: file_path, status_bar: status_bar}
      ) do
    bank_dir = Path.dirname(file_path) |> Path.basename()
    IO.inspect(bank_dir, label: "Bank dir")

    code =
      case bank_dir do
        "UMB" -> "MB"
        "ABSA" -> "BB"
        "Ecobank" -> "EB"
        "GT" -> "GB"
      end

    result = BankRecon.Ledger.run(code, 2022, 5)
    IO.inspect(result)
    :wxTextCtrl.setValue(text_result, "working")
    {:noreply, state}
  end
end
