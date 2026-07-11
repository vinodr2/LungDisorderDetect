object frameSignal: TframeSignal
  Left = 0
  Top = 0
  Width = 900
  Height = 520
  TabOrder = 0
  object pnlLeft: TPanel
    Left = 0
    Top = 0
    Width = 250
    Height = 520
    Align = alLeft
    BevelOuter = bvNone
    ShowCaption = False
    TabOrder = 0
    object lblNets: TLabel
      Left = 0
      Top = 0
      Width = 250
      Height = 20
      Align = alTop
      Caption = '  Networks (tick to plot)'
      Layout = tlCenter
      ExplicitWidth = 130
    end
    object clbNets: TCheckListBox
      Left = 0
      Top = 20
      Width = 250
      Height = 260
      Align = alClient
      ItemHeight = 17
      TabOrder = 0
      OnClick = clbNetsClick
      OnClickCheck = clbNetsClickCheck
    end
    object pnlCompare: TPanel
      Left = 0
      Top = 280
      Width = 250
      Height = 240
      Align = alBottom
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 1
      object lblCompare: TLabel
        Left = 8
        Top = 6
        Width = 118
        Height = 15
        Caption = 'Snapshot comparison'
      end
      object lblFrom: TLabel
        Left = 8
        Top = 32
        Width = 28
        Height = 15
        Caption = 'From'
      end
      object lblTo: TLabel
        Left = 8
        Top = 61
        Width = 16
        Height = 15
        Caption = 'To'
      end
      object cboOlder: TComboBox
        Left = 44
        Top = 28
        Width = 120
        Height = 23
        Style = csDropDownList
        TabOrder = 0
      end
      object cboNewer: TComboBox
        Left = 44
        Top = 57
        Width = 120
        Height = 23
        Style = csDropDownList
        TabOrder = 1
      end
      object btnCompare: TButton
        Left = 170
        Top = 28
        Width = 72
        Height = 52
        Caption = 'Compare'
        TabOrder = 2
        OnClick = btnCompareClick
      end
      object lstDiff: TListBox
        Left = 0
        Top = 92
        Width = 250
        Height = 148
        Align = alBottom
        ItemHeight = 15
        TabOrder = 3
      end
    end
  end
  object pbGauges: TPaintBox
    Left = 250
    Top = 350
    Width = 650
    Height = 170
    Align = alBottom
    OnPaint = pbGaugesPaint
    ExplicitLeft = 250
    ExplicitTop = 350
  end
  object pbGraph: TPaintBox
    Left = 250
    Top = 0
    Width = 650
    Height = 350
    Align = alClient
    OnPaint = pbGraphPaint
    ExplicitLeft = 250
    ExplicitTop = 0
  end
end
