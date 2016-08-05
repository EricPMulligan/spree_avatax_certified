module SpreeAvataxCertified
  class Line
    attr_reader :order, :lines

    def initialize(order, invoice_type, refund = nil)
      @logger ||= AvataxHelper::AvataxLog.new('avalara_order_lines', 'SpreeAvataxCertified::Line', "Building Lines for Order#: #{order.number}")
      @order = order
      @invoice_type = invoice_type
      @lines = []
      @refund = refund
      @refunds = []
      build_lines
      @logger.debug @lines
    end

    def build_lines
      if %w(ReturnInvoice ReturnOrder).include?(@invoice_type)
        refund_lines
      else
        item_lines_array
        shipment_lines_array
      end
    end

    def item_line(line_item)
      {
        LineNo: "#{line_item.id}-LI",
        Description: line_item.name[0..255],
        TaxCode: line_item.tax_category.try(:tax_code) || 'P0000000',
        ItemCode: line_item.variant.sku,
        Qty: line_item.quantity,
        Amount: line_item.discounted_amount.to_f,
        OriginCode: get_stock_location(line_item),
        DestinationCode: 'Dest',
        CustomerUsageType: order.customer_usage_type,
        Discounted: true,
        TaxIncluded: tax_included_in_price?(line_item)
      }
    end

    def item_lines_array
      order.line_items.each do |line_item|
        lines << item_line(line_item)
      end
    end

    def shipment_lines_array
      order.shipments.each do |shipment|
        next unless shipment.tax_category
        lines << shipment_line(shipment)
      end
    end

    def shipment_line(shipment)
      {
        LineNo: "#{shipment.id}-FR",
        ItemCode: shipment.shipping_method.name,
        Qty: 1,
        Amount: shipment.discounted_amount.to_f,
        OriginCode: "#{shipment.stock_location_id}",
        DestinationCode: 'Dest',
        CustomerUsageType: order.customer_usage_type,
        Description: 'Shipping Charge',
        TaxCode: shipment.shipping_method_tax_code,
        Discounted: false,
        TaxIncluded: tax_included_in_price?(shipment)
      }
    end

    def refund_lines
      return lines << refund_line if @refund.reimbursement.nil?

      return_items = @refund.reimbursement.customer_return.return_items
      inventory_units = Spree::InventoryUnit.where(id: return_items.pluck(:inventory_unit_id))

      inventory_units.group_by(&:line_item_id).each_value do |inv_unit|

        inv_unit_ids = inv_unit.map { |iu| iu.id }
        return_items = Spree::ReturnItem.where(inventory_unit_id: inv_unit_ids)
        quantity = inv_unit.uniq.count
        amount = return_items.sum(:pre_tax_amount)

        lines << return_item_line(inv_unit.first.line_item, quantity, amount)
      end
    end

    def refund_line
      {
        LineNo: "#{@refund.id}-RA",
        ItemCode: @refund.transaction_id || 'Refund',
        Qty: 1,
        Amount: -return_amount.to_f,
        OriginCode: 'Orig',
        DestinationCode: 'Dest',
        CustomerUsageType: order.customer_usage_type,
        Description: 'Refund'
      }
    end

    def return_amount
      if @refund.payment.amount < @refund.amount
        item_total = @order.item_total
        item_tax_total = @order.all_adjustments.where(adjustable_type: 'Spree::LineItem').sum(:amount)

        tax_rate = item_tax_total / item_total
        tax_rate * @refund.amount
      else
        @order.total.to_f - @order.all_adjustments.tax.sum(:amount)
      end
    end

    def return_item_line(line_item, quantity, amount)
      {
        LineNo: "#{line_item.id}-LI",
        Description: line_item.name[0..255],
        TaxCode: line_item.tax_category.try(:tax_code) || 'P0000000',
        ItemCode: line_item.variant.sku,
        Qty: quantity,
        Amount: -amount.to_f,
        OriginCode: get_stock_location(line_item),
        DestinationCode: 'Dest',
        CustomerUsageType: order.customer_usage_type
      }
    end

    def get_stock_location(li)
      inventory_units = li.inventory_units

      return 'Orig' if inventory_units.blank?

      stock_loc_id = inventory_units.first.try(:shipment).try(:stock_location_id)

      stock_loc_id.nil? ? 'Orig' : "#{stock_loc_id}"
    end

    def tax_included_in_price?(item)
      if item.tax_category.try(:tax_rates).any?
        item.tax_category.tax_rates.first.included_in_price
      else
        false
      end
    end

  end
end
