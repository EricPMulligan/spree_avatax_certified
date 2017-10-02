require 'spec_helper'

describe Spree::AvalaraTransaction, :type => :model do

  it { should belong_to :order }
  it { should validate_presence_of :order }
  it { should validate_uniqueness_of :order_id }
  it { should have_db_index :order_id }
  it { should have_many :adjustments }

  let(:order) {
    order = create(:order_with_line_items)
    order.reload
  }
  let!(:rate) { create(:avalara_tax_rate, tax_category: order.line_items.first.tax_category) }

  before :each do
    MyConfigPreferences.set_preferences
    stock_location = FactoryGirl.create(:stock_location)
    order.line_items.first.tax_category.update_attributes(name: "Clothing", description: "PC030000")
  end

  context 'captured orders' do

    before :each do
      order.avalara_capture
    end

    describe "#lookup_avatax" do
      it "should look up avatax" do
        expect(order.avalara_transaction.lookup_avatax["TotalTax"]).to eq("2")
      end
    end

    describe "#commit_avatax" do
      it "should commit avatax" do
        expect(order.avalara_transaction.commit_avatax('SalesInvoice')["TotalTax"]).to eq("2")
      end

      it 'should receive post_order_to_avalara' do
        expect(order.avalara_transaction).to receive(:post_order_to_avalara)
        order.avalara_transaction.commit_avatax('SalesInvoice')
      end

      context 'tax calculation disabled' do
        it 'should respond with total tax of 0' do
          Spree::Config.avatax_tax_calculation = false
          expect(order.avalara_transaction.commit_avatax('SalesInvoice')[:TotalTax]).to eq("0.00")
        end
      end


      context 'included_in_price' do
        before do
          rate.update_attributes(included_in_price: true)
          order.reload
        end

        it 'calculates the included tax amount from item total' do
          expect(order.avalara_transaction.commit_avatax('SalesOrder')["TotalTax"]).to eq("1.9")
        end
      end

      context 'included_in_price' do
        before do
          rate.update_attributes(included_in_price: true)
          order.reload
        end

        it 'calculates the included tax amount from item total' do
          expect(order.avalara_transaction.commit_avatax('SalesOrder')["TotalTax"]).to eq("1.9")
        end
      end
    end

    describe "#commit_avatax_final" do
      context 'old tests' do
        before do
          allow(order).to receive(:tax_application).and_return nil
        end

        it "should commit avatax final" do
          expect(order.avalara_transaction.commit_avatax_final('SalesInvoice')["TotalTax"]).to eq("2")
        end

        it 'should receive post_order_to_avalara' do
          expect(order.avalara_transaction).to receive(:post_order_to_avalara)
          order.avalara_transaction.commit_avatax_final('SalesInvoice')
        end

        it "should fail to commit to avatax if settings are false" do
          Spree::Config.avatax_document_commit = false

          expect(order.avalara_transaction.commit_avatax_final('SalesInvoice')).to eq("avalara document committing disabled")
        end

        context 'tax calculation disabled' do
          it 'should respond with total tax of 0' do
            Spree::Config.avatax_tax_calculation = false
            expect(order.avalara_transaction.commit_avatax_final('SalesInvoice')[:TotalTax]).to eq("0.00")
          end
        end

      end

      context 'FS global tax collection is off' do

        shared_examples 'commits based on Fullscript order tax app' do
          it "should commit avatax" do
            expect(order.avalara_transaction.commit_avatax_final('SalesInvoice')["TotalTax"]).to eq("2")
          end

          it 'should receive post_order_to_avalara' do
            expect(order.avalara_transaction).to receive(:post_order_to_avalara)
            order.avalara_transaction.commit_avatax_final('SalesInvoice')
          end
        end

        shared_examples 'no commit based on Fullscript order tax application' do
          it "should not commit avatax" do
            expect(order.avalara_transaction.commit_avatax_final('SalesInvoice')[:TotalTax]).to eq("0.00")
          end

          it 'should not receive post_order_to_avalara' do
            expect(order.avalara_transaction).to_not receive(:post_order_to_avalara)
            order.avalara_transaction.commit_avatax_final('SalesInvoice')
          end
        end

        context 'taxes off globally' do
          before do
            allow(order).to receive(:tax_application).and_return 'none'
          end
          it_behaves_like 'no commit based on Fullscript order tax application'
        end

        context 'taxes off for store' do
          before do
            allow(order).to receive(:tax_application).and_return 'store'
          end
          it_behaves_like 'no commit based on Fullscript order tax application'
        end

        context 'avalara tax calc success' do
          before do
            allow(order).to receive(:tax_application).and_return 'avatax'
          end
          it_behaves_like 'commits based on Fullscript order tax app'
        end

        context 'tax_application not set' do
          before do
            allow(order).to receive(:tax_application).and_return nil
          end
          it_behaves_like 'commits based on Fullscript order tax app'
        end

      end

    end

    describe '#cancel_order' do
      it 'should receive cancel_order_to_avalara' do
        expect(order.avalara_transaction).to receive(:cancel_order_to_avalara)
        order.avalara_transaction.cancel_order
      end
    end
  end
end
