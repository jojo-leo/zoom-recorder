# Meeting management window (WPF). Lives in the module so click-handler closures (GetNewClosure)
# can resolve these functions; form logic is in MeetingForm.ps1.

Add-Type -AssemblyName PresentationFramework

function New-XamlWindow {
    param([string]$Xaml)
    [xml]$doc = $Xaml
    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $doc))
    $controls = @{}
    $doc.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
        $name = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        $controls[$name] = $window.FindName($name)
    }
    @{ Window = $window; C = $controls }
}

function Show-AddEditDialog {
    param($Meeting, $Owner)
    $ui = New-XamlWindow @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="会议" Width="460" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" FontFamily="Microsoft YaHei UI" FontSize="13">
  <Grid Margin="20">
    <Grid.ColumnDefinitions><ColumnDefinition Width="110"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="会议名称" VerticalAlignment="Center"/>
    <TextBox Grid.Row="0" Grid.Column="1" x:Name="NameBox" Margin="0,4"/>
    <TextBlock Grid.Row="1" Text="会议号 *" VerticalAlignment="Center"/>
    <TextBox Grid.Row="1" Grid.Column="1" x:Name="NumberBox" Margin="0,4"/>
    <TextBlock Grid.Row="2" Text="密码" VerticalAlignment="Center"/>
    <TextBox Grid.Row="2" Grid.Column="1" x:Name="PasswordBox" Margin="0,4"/>
    <TextBlock Grid.Row="3" Text="日期 *" VerticalAlignment="Center"/>
    <DatePicker Grid.Row="3" Grid.Column="1" x:Name="DateBox" Margin="0,4" SelectedDateFormat="Short"/>
    <TextBlock Grid.Row="4" Text="时间 (HH:mm) *" VerticalAlignment="Center"/>
    <TextBox Grid.Row="4" Grid.Column="1" x:Name="TimeBox" Margin="0,4" Text="15:00"/>
    <TextBlock Grid.Row="5" Text="会议原时区 *" VerticalAlignment="Center"/>
    <ComboBox Grid.Row="5" Grid.Column="1" x:Name="ZoneBox" Margin="0,4"/>
    <TextBlock Grid.Row="6" Text="最长时长 (分钟)" VerticalAlignment="Center"/>
    <TextBox Grid.Row="6" Grid.Column="1" x:Name="DurationBox" Margin="0,4" Text="120"/>
    <TextBlock Grid.Row="7" Grid.ColumnSpan="2" x:Name="Preview" Margin="0,12,0,4" FontWeight="Bold" Foreground="#1565C0" TextWrapping="Wrap"/>
    <StackPanel Grid.Row="8" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="SaveBtn" Content="保存" Width="90" Height="30" Margin="0,0,10,0" IsDefault="True"/>
      <Button x:Name="CancelBtn" Content="取消" Width="90" Height="30" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $w = $ui.Window; $c = $ui.C
    if ($Owner) { $w.Owner = $Owner }
    Get-SupportedTimeZones | ForEach-Object { [void]$c.ZoneBox.Items.Add($_) }
    $c.ZoneBox.SelectedItem = 'America/New_York'
    $c.DateBox.SelectedDate = (Get-Date).Date.AddDays(1)

    if ($Meeting) {
        $orig = [datetime]::ParseExact($Meeting.originalTime, 'yyyy-MM-ddTHH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
        $w.Title = '编辑会议'
        $c.NameBox.Text = $Meeting.name; $c.NumberBox.Text = $Meeting.meetingID; $c.PasswordBox.Text = $Meeting.password
        $c.DateBox.SelectedDate = $orig.Date; $c.TimeBox.Text = $orig.ToString('HH:mm')
        $c.ZoneBox.SelectedItem = $Meeting.originalTimeZone; $c.DurationBox.Text = [string]$Meeting.maxDuration
    } else { $w.Title = '添加会议' }

    $readForm = {
        @{
            Name = $c.NameBox.Text; MeetingID = $c.NumberBox.Text; Password = $c.PasswordBox.Text
            Date = $c.DateBox.SelectedDate; Time = $c.TimeBox.Text.Trim(); TimeZone = [string]$c.ZoneBox.SelectedItem
            MaxDuration = $c.DurationBox.Text.Trim()
        }
    }.GetNewClosure()

    $preview = {
        $f = & $readForm
        $t = [datetime]::MinValue
        if (-not $f.Date -or -not [datetime]::TryParseExact($f.Time, 'H:mm', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$t)) {
            $c.Preview.Text = '珀斯时间：—'; return
        }
        try {
            $p = ConvertTo-PerthTime ([datetime]$f.Date).Date.Add($t.TimeOfDay) $f.TimeZone
            $c.Preview.Text = "珀斯时间：$($p.ToString('yyyy-MM-dd HH:mm')) (AWST)"
            $c.Preview.Foreground = '#1565C0'
        } catch {
            $c.Preview.Text = $_.Exception.Message
            $c.Preview.Foreground = '#C62828'
        }
    }.GetNewClosure()
    $c.TimeBox.add_TextChanged($preview); $c.DateBox.add_SelectedDateChanged($preview); $c.ZoneBox.add_SelectionChanged($preview)
    & $preview

    $state = @{ Saved = $false }
    $c.SaveBtn.add_Click({
            $form = & $readForm
            $r = Save-MeetingFromForm $form -Existing $Meeting
            if ($r.Errors.Count) {
                [void][Windows.MessageBox]::Show(($r.Errors -join "`n"), '无法保存', 'OK', 'Warning'); return
            }
            if (-not $r.Ok -and $r.Conflicts.Count) {
                $names = ($r.Conflicts | ForEach-Object { "· $($_.name)  $($_.perthTime.Replace('T', ' '))" }) -join "`n"
                $answer = [Windows.MessageBox]::Show("与以下会议时间重叠（同一时间只能录一场）：`n$names`n`n仍要保存吗？", '时间冲突', 'YesNo', 'Warning')
                if ($answer -ne 'Yes') { return }
                $r = Save-MeetingFromForm $form -Existing $Meeting -Force
            }
            if ($r.Ok) { $state.Saved = $true; $w.Close() }
        }.GetNewClosure())

    [void]$w.ShowDialog()
    $state.Saved
}

function Show-MainWindow { [void](New-MainWindow).ShowDialog() }

function New-MainWindow {
    $ui = New-XamlWindow @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ZoomRecorder - 会议管理" Width="900" Height="480" WindowStartupLocation="CenterScreen"
        FontFamily="Microsoft YaHei UI" FontSize="13">
  <DockPanel Margin="12">
    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,10">
      <Button x:Name="AddBtn" Content="添加" Width="80" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="EditBtn" Content="编辑" Width="80" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="DeleteBtn" Content="删除" Width="80" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="RefreshBtn" Content="刷新" Width="80" Height="28"/>
    </StackPanel>
    <TextBlock DockPanel.Dock="Bottom" Margin="0,8,0,0" Foreground="Gray"
               Text="录制时请：不锁屏（Win+L）、不合盖、接上电源。录像保存在 D:\EV录屏文件，日志在 Logs 文件夹。"/>
    <DataGrid x:Name="Grid" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single" HeadersVisibility="Column">
      <DataGrid.Columns>
        <DataGridTextColumn Header="会议名称" Binding="{Binding Name}" Width="*"/>
        <DataGridTextColumn Header="会议号" Binding="{Binding Number}" Width="120"/>
        <DataGridTextColumn Header="原时区时间" Binding="{Binding Original}" Width="250"/>
        <DataGridTextColumn Header="珀斯时间" Binding="{Binding Perth}" Width="170"/>
        <DataGridTextColumn Header="状态" Binding="{Binding Status}" Width="70"/>
      </DataGrid.Columns>
    </DataGrid>
  </DockPanel>
</Window>
'@
    $w = $ui.Window; $c = $ui.C

    $refresh = {
        try { $meetings = @(Get-Meetings) } catch {
            [void][Windows.MessageBox]::Show($_.Exception.Message, '读取失败', 'OK', 'Error'); $meetings = @()
        }
        $c.Grid.ItemsSource = @($meetings | Sort-Object perthTime -Descending | ForEach-Object {
                $times = Format-MeetingTimes $_
                [pscustomobject]@{
                    Name = $_.name; Number = Format-MeetingNumber $_.meetingID; Original = $times.Original
                    Perth = $times.Perth; Status = Get-StatusLabel $_.status; Meeting = $_
                }
            })
    }.GetNewClosure()

    $edit = {
        $row = $c.Grid.SelectedItem
        if (-not $row) { return }
        if ($row.Meeting.status -in 'guarding', 'recording') {
            [void][Windows.MessageBox]::Show('这场会议正在值守或录制中，不能编辑。', '提示', 'OK', 'Information'); return
        }
        if (Show-AddEditDialog -Meeting $row.Meeting -Owner $w) { & $refresh }
    }.GetNewClosure()

    $c.AddBtn.add_Click({ if (Show-AddEditDialog -Owner $w) { & $refresh } }.GetNewClosure())
    $c.EditBtn.add_Click($edit)
    $c.Grid.add_MouseDoubleClick($edit)
    $c.RefreshBtn.add_Click($refresh)
    $c.DeleteBtn.add_Click({
            $row = $c.Grid.SelectedItem
            if (-not $row) { return }
            if ($row.Meeting.status -in 'guarding', 'recording') {
                [void][Windows.MessageBox]::Show('这场会议正在值守或录制中，请先在托盘菜单中停止录制。', '提示', 'OK', 'Information'); return
            }
            $answer = [Windows.MessageBox]::Show("确定删除「$($row.Name)」吗？对应的定时任务也会删除。", '确认删除', 'YesNo', 'Question')
            if ($answer -eq 'Yes') { Remove-MeetingWithTasks $row.Meeting.id; & $refresh }
        }.GetNewClosure())

    & $refresh
    $w
}
