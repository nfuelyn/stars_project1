param([string]$Path)
$xml = [xml](Get-Content -LiteralPath $Path -Raw)
$script:sb = New-Object System.Text.StringBuilder
function Pad([int]$n){ return (' ' * $n) }
function W([string]$s){ [void]$script:sb.AppendLine($s) }
function GetParams($node){
  $list = @()
  foreach($p in $node.SelectNodes('./param')){
    $v = $p.InnerText
    if($p.name -ne ''){ $list += ($p.name + '=' + $v) } else { $list += $v }
  }
  return ($list -join ', ')
}
function EmitCond($c, [int]$ind){
  $inv = ''
  if(($c.inverted -eq 'true') -or ($c.inverted -eq '1')){ $inv = ' [INVERTED]' }
  $ps = GetParams $c
  $extra = ''
  if($ps -ne ''){ $extra = '  (' + $ps + ')' }
  W ((Pad $ind) + 'IF ' + $c.type + ' :: ' + $c.name + $inv + $extra)
  foreach($sub in $c.SelectNodes('./conditions/condition')){ EmitCond $sub ($ind+2) }
}
function EmitCondBlock($condNode, [int]$ind){
  if($null -eq $condNode){ return }
  $kids = @($condNode.SelectNodes('./condition'))
  $or = @($kids | Where-Object { $_.name -eq 'Or' })
  if(($or.Count -gt 0) -and ($kids.Count -eq 1)){
    W ((Pad $ind) + 'IF ANY-OF:')
    foreach($sub in $or[0].SelectNodes('./conditions/condition')){ EmitCond $sub ($ind+2) }
  } else {
    foreach($c in $kids){ EmitCond $c $ind }
  }
}
function EmitAction($a, [int]$ind){
  $ps = GetParams $a
  $extra = ''
  if($ps -ne ''){ $extra = '  (' + $ps + ')' }
  W ((Pad $ind) + 'DO ' + $a.type + ' :: ' + $a.name + $extra)
}
function EmitNode($e, [int]$ind){
  if($null -eq $e){ return }
  switch($e.LocalName){
    'event-block' {
      $dis = ''
      if($e.disabled -eq 'true'){ $dis = ' (DISABLED)' }
      if($e.any -eq '1'){ $kids=@($e.SelectNodes('./conditions/condition')); W ((Pad ($ind+2)) + 'IF ANY-OF (OR):'); foreach($cond in $kids){ EmitCond $cond ($ind+4) } } else { EmitCondBlock ($e.SelectSingleNode('./conditions')) ($ind+2) }
      foreach($a in $e.SelectNodes('./actions/action')){ EmitAction $a ($ind+2) }
      foreach($sub in $e.SelectNodes('./sub-events/child::*')){ EmitNode $sub ($ind+4) }
    }
    'event-group' {
      W ((Pad $ind) + '===== GROUP: ' + $e.title + '  |  ' + $e.description)
      foreach($sub in $e.SelectNodes('./sub-events/child::*')){ EmitNode $sub ($ind+2) }
    }
    'comment' { W ((Pad $ind) + '// ' + (($e.InnerText) -replace "`r?`n", ' ')) }
    'variable' {
      $cn = ''
      if($e.constant -eq '1'){ $cn = ' [const]' }
      W ((Pad $ind) + 'VAR ' + $e.name + ' (' + $e.type + ') = ' + $e.InnerText + $cn)
    }
    'function' {
      $pars = @($e.SelectNodes('./parameters/parameter') | ForEach-Object { $_.name })
      W ((Pad $ind) + 'FUNCTION ' + $e.name + '(' + ($pars -join ', ') + ')')
      foreach($sub in $e.SelectNodes('./sub-events/child::*')){ EmitNode $sub ($ind+2) }
    }
    'include' { W ((Pad $ind) + 'INCLUDE ' + $e.eventSheet) }
    default { W ((Pad $ind) + '<' + $e.LocalName + '>') }
  }
}
foreach($top in $xml.c2eventsheet.events.ChildNodes){ EmitNode $top 0 }
$out = Join-Path 'D:\stars\_analysis' ((Split-Path $Path -Leaf) + '.txt')
Set-Content -LiteralPath $out -Value $script:sb.ToString() -Encoding UTF8



