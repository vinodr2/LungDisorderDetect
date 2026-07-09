object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Wi-Fi Analyzer'
  ClientHeight = 561
  ClientWidth = 1024
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 15
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 1024
    Height = 44
    Align = alTop
    BevelOuter = bvNone
    Padding.Left = 8
    Padding.Right = 8
    ShowCaption = False
    TabOrder = 0
    object lblSearch: TLabel
      Left = 12
      Top = 15
      Width = 42
      Height = 15
      Caption = 'Search:'
    end
    object lblBand: TLabel
      Left = 320
      Top = 15
      Width = 31
      Height = 15
      Caption = 'Band:'
    end
    object lblInterval: TLabel
      Left = 470
      Top = 15
      Width = 45
      Height = 15
      Caption = 'Interval:'
    end
    object edtSearch: TEdit
      Left = 60
      Top = 11
      Width = 240
      Height = 23
      TabOrder = 0
      TextHint = 'SSID, BSSID or vendor'
      OnChange = edtSearchChange
    end
    object cboBand: TComboBox
      Left = 357
      Top = 11
      Width = 100
      Height = 23
      Style = csDropDownList
      ItemIndex = 0
      TabOrder = 1
      Text = 'All bands'
      OnChange = cboBandChange
      Items.Strings = (
        'All bands'
        '2.4 GHz'
        '5 GHz'
        '6 GHz')
    end
    object cboInterval: TComboBox
      Left = 521
      Top = 11
      Width = 90
      Height = 23
      Style = csDropDownList
      TabOrder = 2
      OnChange = cboIntervalChange
    end
    object btnRefresh: TButton
      Left = 625
      Top = 10
      Width = 90
      Height = 25
      Caption = 'Rescan now'
      TabOrder = 3
      OnClick = btnRefreshClick
    end
    object chkDark: TCheckBox
      Left = 730
      Top = 14
      Width = 100
      Height = 17
      Caption = 'Dark mode'
      TabOrder = 4
      OnClick = chkDarkClick
    end
  end
  object pgcMain: TPageControl
    Left = 0
    Top = 44
    Width = 1024
    Height = 498
    ActivePage = tsNetworks
    Align = alClient
    TabOrder = 1
    object tsNetworks: TTabSheet
      Caption = 'Networks'
      object grdNetworks: TDrawGrid
        Left = 0
        Top = 0
        Width = 1016
        Height = 468
        Align = alClient
        ColCount = 12
        DefaultColWidth = 100
        DefaultRowHeight = 22
        FixedCols = 0
        RowCount = 2
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect, goThumbTracking]
        TabOrder = 0
        OnDrawCell = grdNetworksDrawCell
        OnMouseDown = grdNetworksMouseDown
      end
    end
    object tsChannels: TTabSheet
      Caption = 'Channels'
      ImageIndex = 1
    end
    object tsSignal: TTabSheet
      Caption = 'Signal'
      ImageIndex = 2
    end
  end
  object sbMain: TStatusBar
    Left = 0
    Top = 542
    Width = 1024
    Height = 19
    Panels = <>
    SimplePanel = True
    SimpleText = 'Starting...'
  end
  object tmrUi: TTimer
    Interval = 1000
    OnTimer = tmrUiTimer
    Left = 900
    Top = 80
  end
end
