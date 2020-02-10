# frozen_string_literals: true

require_relative '../../src/story'

describe Story do
  describe '#traverse' do
    let(:starting_vars) { {} }
    let(:results) { subject.traverse('intro', starting_vars) }

    before do
      allow(subject).to receive(:warn_cycle)
      allow(subject).to receive(:warn_deadend)
      allow(subject).to receive(:warn_decrement)
      allow(subject).to receive(:warn_ending)
    end

    context 'with a single-node YML file' do
      subject { described_class.new('spec/src/data/single_node.yml') }

      it 'does not raise an error' do
        expect { results }.not_to raise_error
      end

      it 'returns an array' do
        expect(results).to be_an(Array)
      end

      it 'returns one traversal path' do
        expect(results.length).to eq(1)
      end

      it 'returns the crumb path "intro"' do
        expect(results[0]['crumbs']).to eq(['intro'])
      end

      it 'returns no vars' do
        expect(results[0]['vars']).to eq({})
      end
    end

    context 'with a two-node YML file' do
      subject { described_class.new('spec/src/data/two_nodes.yml') }

      it 'does not raise an error' do
        expect { subject.traverse('intro') }.not_to raise_error
      end

      it 'returns an array' do
        expect(results).to be_an(Array)
      end

      it 'returns one traversal path' do
        expect(results.length).to eq(1)
      end

      it 'returns the crumb path "intro -> ending"' do
        expect(results[0]['crumbs']).to eq(['intro', 'ending'])
      end

      it 'returns a vars hash' do
        expect(results[0]['vars']).to be_a(Hash)
      end

      it 'returns the flag reached_ending = true' do
        expect(results[0]['vars']['reached_ending']).to eq(true)
      end

      it 'returns the value "step" = 2' do
        expect(results[0]['vars']['step']).to eq(2)
      end
    end

    context 'when a decrement drops a variable below zero' do
      subject { described_class.new('spec/src/data/decrement_warning.yml') }

      it 'warns the user if a decrement drops a var below zero' do
        allow(subject).to receive(:warn_decrement)

        results

        expect(subject).to have_received(:warn_decrement)
      end
    end

    context 'when a self-reference is detected' do
      subject { described_class.new('spec/src/data/selfref.yml') }

      it 'warns the user of a cycle' do
        allow(subject).to receive(:warn_cycle)

        results

        expect(subject).to have_received(:warn_cycle)
      end
    end

    context 'when a self-reference is detected' do
      subject { described_class.new('spec/src/data/three-node-cycle.yml') }

      it 'warns the user of a cycle' do
        allow(subject).to receive(:warn_cycle)

        results

        expect(subject).to have_received(:warn_cycle)
      end
    end

    context 'with a conditional YML file' do
      subject { described_class.new('spec/src/data/conditional_nodes.yml') }

      it 'does not raise an error' do
        expect { subject.traverse('intro') }.not_to raise_error
      end

      it 'returns an array' do
        expect(results).to be_an(Array)
      end

      context 'with default vars' do
        it 'returns a single traversal path' do
          expect(results.length).to eq(1)
        end

        it 'returns the crumb path "intro"' do
          expect(results[0]['crumbs']).to eq(['intro'])
        end

        it 'warns the user of a dead-end' do
          allow(subject).to receive(:warn_deadend)

          results

          expect(subject).to have_received(:warn_deadend)
        end
      end

      context 'with flag set' do
        let(:starting_vars) { { 'can_reach_flag_node' => true } }

        it 'returns one traversal path' do
          expect(results.length).to eq(1)
        end
      end

      context 'with value set' do
        let(:starting_vars) { { 'must_exceed_three' => 5 } }

        it 'returns one traversal path' do
          expect(results.length).to eq(1)
        end
      end

      context 'with both set' do
        let(:starting_vars) do
          {
            'can_reach_flag_node' => true,
            'must_exceed_three' => 5
          }
        end

        it 'returns two traversal paths' do
          expect(results.length).to eq(2)
        end
      end
    end
  end
end
