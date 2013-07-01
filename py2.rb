#! /usr/bin/env ruby
#
# py2.rb -- A first pass at porting Python source code to Ruby.
#           Reads Python code from stdin and writes Ruby code to stdout.
#
# This script just does the obvious, easy transformations, giving you more time to work on the harder ones :)
# It is NOT a real parser, just a bunch of kludgy regex operations, so it can't do anything fancy.
# It may get some things wrong, and won't even attempt some other things that it's very likely to get wrong.
# The output will definitely have to be hand edited by someone familiar with both languages, before it can
# be expected to compile as Ruby, much less run correctly. The goal is simply to require _less_ hand editing,
# and less mechanical replacing, than you would have had to do without this script.
#
# Version 2 ... by Jens Alfke, 1 May 2010. 
# Placed in the public domain. "Do what thou wilt" shall be the whole of the law.
# I'd appreciate it if you contributed improvements or fixes back to the repository, though!
# http://bitbucket.org/snej/py2rb


INDENT_WIDTH = 2            # Indentation width assumed in the input Python code


# Python reserved words mapped to Ruby equivalents
ReservedWordMap = {
  'None'      => 'nil',
  'True'      => 'true',
  'False'     => 'false',
  'elif'      => 'elsif',
  '\s*is'     => '.equal?',
  '\s*is not' => '.not_equal?',   # Doesn't actually exist; you'll have to convert it to != by hand
  'end'       => 'end_',          # not reserved in Python but is in Ruby, so rename it
}

# Python functions mapped to Ruby methods
FunctionsToMethods = {
  'len' => 'length',
  'str' => 'to_s',
  'int' => 'to_i',
}

# Python functions mapped to Ruby functions
FunctionsToFunctions = {
  'open' => 'File.open',
}

# Special method names for constructors and operator overloading
SpecialMethods = {
  '__init__'    => 'initialize',
  '__eq__'      => '==',
  '__str__'     => 'to_s',
  '__repr__'    => 'to_s',
  '__getitem__' => '[]',
  '__setitem__' => '[]=',
  # Incomplete so far; add any extra ones you need.
}


# Global variables:
$line = ''                  # Current line being translated, trimmed of whitespace
$indentStr = ''             # The leading whitespace before $line
$indent = 0                 # The character width of the leading whitespace
$lastIndent = 0             # The indent of the previous line
$blankLines = 0             # The number of consecutive blank lines being skipped
$continuation = false       # Set to true when $line ends with a "\"
$classname = "???"          # Name of the last class definition entered
$methodIsStatic = false     # Set to true when "@staticmethod" or "@classmethod" is seen
$methodIsProperty = false   # Set to true when "@property" is seen


# Returns the width of a string in characters, interpreting tabs as 8 chars wide.
def indentWidth(str)
  width = 0
  str.each_byte do |ch|
    if ch == '\t' then
      width = (width + 7) / 8
    else
      width += 1
    end
  end
  return width
end

# Updates $indent and $indentStr.
def setIndent(indent)
  $indent = indent
  $indentStr = " "*$indent
end

# Assuming $line starts with a triple-quote Python block comment, emits the entire comment as a regular
# comment prefixed with "#" characters.
def emitBlockComment()
  $line = $line[3..-1]
  begin
    $line = $line.strip
    if $line =~ /'''$/
      $line = $line[0..-4]
      puts($indentStr + '# ' + $line)
      break
    end
    puts($indentStr + '# ' + $line)
  end while $line = gets
end

# Compare $indent to $lastIndent and write the appropriate "end" lines. Also writes earlier blank lines.
def emitEndsAndBlanks()
  # If de-indenting, emit 'end' lines:
  while $indent < $lastIndent
    $lastIndent -= INDENT_WIDTH
    $lastIndent = 0  if $lastIndent < 0
    break  if $lastIndent == $indent and ($line=="else" || $line=~/^except/)
    puts((" "*$lastIndent) + "end")
  end
  $lastIndent = $indent
  
  # Add any earlier blank lines (so they come after the 'end', if any)
  $blankLines.times {puts($indentStr)}
  $blankLines = 0
end

def convertFunction(fn, args)
  method = FunctionsToMethods[fn]
  if method then
    args = "(#{args})"  unless args.match(/[\w\s.]/)
    return "#{args}.#{method}"
  end
  rubyfn = FunctionsToFunctions[fn]
  return "#{rubyfn}(#{args})"  if rubyfn
  return "#{fn}(#{args})"
end


# OK, main loop starts here!
while $line = gets()
  # Trim leading whitespace from $line but keep track of its width in $indent.
  match = /^(\s*)(.*)$/.match($line)
  $lastIndent = $indent
  setIndent( indentWidth(match[1]) )
  $line = match[2].rstrip
  
  # Various expression-level transformations:
  $line.gsub!(/r'([^']*)'/, '/\1/')                   # Python raw strings to Ruby rexexps
  
  $line.gsub!(/("[^"]*")\s*%\s*\(/, 'sprintf(\1, ')   # %-style formatting to sprintf
  $line.gsub!(/('[^']*')\s*%\s*\(/, 'sprintf(\1, ')   # Same but with single-quoted strings
  
  # Replace some standard Python functions with equivalent Ruby functions or method calls.
  #TODO: Make sure the preceding char isn't '.', i.e. this isn't already a method call
  $line.gsub!(/\b(\w+)\s*\(([^)]+)\)/) {convertFunction($1,$2)}
  
  unless $line.match(/^class\b/) then
    $line.gsub!(/(\b[A-Z]\w+)\(/, '\1.new(')          # Instantiation: X(...) --> X.new(...)
  end
  
  ReservedWordMap.each_pair do |pyword, rbword|
    $line.gsub!(Regexp.new('\b'+pyword+'\b'), rbword)
  end
  
  $line.gsub!(/\bself\.(\w+\s*)\(/, '\1(')            # Remove "self." before method names
  $line.gsub!(/\bself\._?/, '@')                      # ...and change it to '@' before variables
    
  if $line == "" then
    # Blank line: don't emit it yet, just keep count
    $blankLines += 1
    setIndent($lastIndent)
    
  elsif $line =~ /^'''/ then
    # Triple-quoted string on its own line: convert to a multi-line comment
    emitBlockComment()
    
  elsif $continuation then
    # Continuation line: don't mess with its indent or treat it as a new statement.
    puts($indentStr + $line)
    $continuation = ($line =~ /\\$/)
    setIndent($lastIndent)
    
  else
    # Check if line has a continuation (ends with '\')
    $continuation = $line =~ /\\$/
    $line = $line.chop.rstrip  if $continuation
    
    $line.sub!(/:$/, "")   # Strip trailing ':'
    
    # If indent decreased, emit 'end' statements. Also emit any pending blank lines.
    emitEndsAndBlanks()

    # Handle various types of statements:
    if $line.sub!(/^import\b/, "require")
    elsif $line.sub!(/^from\s+(\w+)\s+import.*$/, 'require \1')
    elsif m = $line.match(/^class\s+(\w+)\s*\((\w+)\)/)
      $classname = m[1]
      $line = "class #{$classname} < #{m[2]}"
    elsif $line == "@staticmethod" or $line == "@classmethod"
      $methodIsStatic = true
      next
    elsif $line == "@property"
      # Ruby syntax doesn't need anything special for this
      next
    elsif m = $line.match(/^def\s+(\w+)\s*\((.*)\)/)
      # Function/method definition:
      name = m[1]
      name = SpecialMethods.fetch(name, name)
      if $methodIsStatic then
        name = "#{$classname}.#{name}"
        $methodIsStatic = false
      end
      $line = "def #{name}"

      args = m[2].strip.split(/\s*,\s*/)
      args.delete_at(0)  if args.length > 0 and args[0] == "self"  # Remove leading 'self' parameter
      $line += " (" + args.join(", ") + ")"  if args.length > 0
    elsif $line.sub!(/^try\b/, "begin")
    elsif $line.sub!(/^except\s+(\w+)\s*,\s*(.*)/, 'rescue \1 => \2')
    elsif $line.sub!(/^except\s+(\w+)\s*as\s*(.*)/, 'rescue \1 => \2')
    elsif m = $line.match(/^with\s+(.*)\s+as\s+(\w+)$/)
      $line = "#{m[1]} do |#{m[2]}|"
    elsif m = $line.match(/^with\s+(.*)$/)
      $line = "#{m[1]} do"
    elsif $line.gsub!(/^assert\s*\((.*)\)$/, 'fail unless \1')
    end
  
    $line += '\\'  if $continuation  # Restore the continuation mark if any
    puts($indentStr + $line)
  end
end

setIndent(0)
emitEndsAndBlanks()
