require 'rspec'
require 'rspec/given/module_methods'

if RSpec::Given::NATURAL_ASSERTIONS_SUPPORTED
  require 'ripper'
  require 'sorcerer'
  require 'rspec/given/monkey'
end

module RSpec
  module Given

    InvalidThenError = Class.new(StandardError)

    class EvalErr
      def initialize(str)
        @string = str
      end
      def size
        inspect.size
      end
      def to_s
        @string
      end
      def inspect
        @string
      end
    end

    class NaturalAssertion

      def initialize(clause_type, block, env, line_extractor)
        @clause_type = clause_type
        @block = block
        @env = env
        @line_extractor = line_extractor
        set_file_and_line
      end

      VOID_SEXP = [:void_stmt]

      def using_rspec_assertion?
        using_should? || using_expect?
      end

      def has_content?
        assertion_sexp != VOID_SEXP
      end

      def message
        @output = "#{@clause_type} expression failed at #{source_line}\n"
        @output << "Failing expression: #{source.strip}\n" if @clause_type != "Then"
        explain_failure
        display_pairs(expression_value_pairs)
        @output << "\n"
        @output
      end

      private

      def using_should?
        source =~ /\.\s*should(_not)?\b/
      end

      def using_expect?
        source =~ /\bexpect\s*[({].*[)}]\s*\.\s*(not_)?to\b/
      end

      BINARY_EXPLAINATIONS = {
        :== => "to equal",
        :!= => "to not equal",
        :<  => "to be less than",
        :<= => "to be less or equal to",
        :>  => "to be greater than",
        :>= => "to be greater or equal to",
        :=~ => "to match",
        :!~ => "to not match",
      }

      def explain_failure
        if assertion_sexp.first == :binary && msg = BINARY_EXPLAINATIONS[assertion_sexp[2]]
          @output << explain_expected("expected", assertion_sexp[1], msg, assertion_sexp[3])
        end
      end

      def explain_expected(expect_msg, expect_sexp, got_msg, got_sexp)
        width = [expect_msg.size, got_msg.size].max
        sprintf("%#{width}s: %s\n%#{width}s: %s\n",
          expect_msg, eval_sexp(expect_sexp),
          got_msg, eval_sexp(got_sexp))
      end

      def expression_value_pairs
        assertion_subexpressions.map { |exp|
          [exp, eval_in(exp, @env)]
        }
      end

      def assertion_subexpressions
        Sorcerer.subexpressions(assertion_sexp).reverse.uniq.reverse
      end

      def assertion_sexp
        @assertion_sexp ||= extract_test_expression(Ripper::SexpBuilder.new(source).parse)
      end

      def source
        @source ||= @line_extractor.line(@code_file, @code_line)
      end

      def set_file_and_line
        @code_file, @code_line = eval "[__FILE__, __LINE__]", @block.binding
        @code_line = @code_line.to_i
      end

      def extract_test_expression(sexp)
        brace_block = extract_brace_block(sexp)
        extract_first_statement(brace_block)
      end

      def extract_brace_block(sexp)
        unless then_block?(sexp)
          source = Sorcerer.source(sexp)
          fail InvalidThenError, "Unexpected code at #{source_line}\n#{source}"
        end
        sexp[1][2][2]
      end

      def then_block?(sexp)
        delve(sexp,0) == :program &&
          delve(sexp,1,0) == :stmts_add &&
          delve(sexp,1,2,0) == :method_add_block &&
          (delve(sexp,1,2,2,0) == :brace_block || delve(sexp,1,2,2,0) == :do_block)
      end

      def extract_first_statement(block_sexp)
        if contains_multiple_statements?(block_sexp)
          source = Sorcerer.source(block_sexp)
          fail InvalidThenError, "Multiple statements in Then block at #{source_line}\n#{source}"
        end
        extract_statement_from_block(block_sexp)
      end

      def contains_multiple_statements?(block_sexp)
        !(delve(block_sexp,2,0) == :stmts_add &&
          delve(block_sexp,2,1,0) == :stmts_new)
      end

      def extract_statement_from_block(block_sexp)
        delve(block_sexp,2,2)
      end

      # Safely dive into an array with a list of indicies. Return nil
      # if the element doesn't exist, or if the intermediate result is
      # not indexable.
      def delve(ary, *indicies)
        result = ary
        while !indicies.empty? && result
          return nil unless result.respond_to?(:[])
          i = indicies.shift
          result = result[i]
        end
        result
      end

      def eval_sexp(sexp)
        expr = Sorcerer.source(sexp)
        eval_in(expr, @env)
      end

      def eval_in(exp, binding)
        eval(exp, binding).inspect
      rescue StandardError => ex
        EvalErr.new("#{ex.class}: #{ex.message}")
      end

      WRAP_WIDTH = 20

      def display_pairs(pairs)
        width = suggest_width(pairs)
        pairs.each do |x, v|
          fmt = (v.size > WRAP_WIDTH) ?
          "  %-#{width+2}s\n  #{' '*(width+2)} <- %s\n" :
            "  %-#{width+2}s <- %s\n"
          @output << sprintf(fmt, v, x)
        end
      end

      def suggest_width(pairs)
        pairs.map { |x,v| v.size }.select { |n| n < WRAP_WIDTH }.max || 10
      end

      def source_line
        "#{@code_file}:#{@code_line}"
      end
    end

  end
end
