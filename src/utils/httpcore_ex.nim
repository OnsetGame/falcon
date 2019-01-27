## WARNING: This module is copy of some of nim cgi module functions,
## should be REMOVED, after this functions will be contributed to httpcore module.

import strutils

proc encodeUrl*(s: string): string =
  ## Encodes a value to be HTTP safe: This means that characters in the set
  ## ``{'A'..'Z', 'a'..'z', '0'..'9', '_'}`` are carried over to the result,
  ## a space is converted to ``'+'`` and every other character is encoded as
  ## ``'%xx'`` where ``xx`` denotes its hexadecimal value.
  result = newStringOfCap(s.len + s.len shr 2) # assume 12% non-alnum-chars
  for i in 0..s.len-1:
    case s[i]
    of 'a'..'z', 'A'..'Z', '0'..'9', '_': add(result, s[i])
    of ' ': add(result, '+')
    else:
      add(result, '%')
      add(result, toHex(ord(s[i]), 2))

proc handleHexChar(c: char, x: var int) {.inline.} =
  case c
  of '0'..'9': x = (x shl 4) or (ord(c) - ord('0'))
  of 'a'..'f': x = (x shl 4) or (ord(c) - ord('a') + 10)
  of 'A'..'F': x = (x shl 4) or (ord(c) - ord('A') + 10)
  else: assert(false)

proc decodeUrl*(s: string): string =
  ## Decodes a value from its HTTP representation: This means that a ``'+'``
  ## is converted to a space, ``'%xx'`` (where ``xx`` denotes a hexadecimal
  ## value) is converted to the character with ordinal number ``xx``, and
  ## and every other character is carried over.
  result = newString(s.len)
  var i = 0
  var j = 0
  while i < s.len:
    case s[i]
    of '%':
      var x = 0
      handleHexChar(s[i+1], x)
      handleHexChar(s[i+2], x)
      inc(i, 2)
      result[j] = chr(x)
    of '+': result[j] = ' '
    else: result[j] = s[i]
    inc(i)
    inc(j)
  setLen(result, j)
