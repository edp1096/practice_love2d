package rulesruntime

import (
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

// Buy purchases an authored shop offer from infinite authored stock. The
// current ShopRule has no finite merchant-stock field, so CanBuy is the stock
// availability contract. Offer price, quantity, player stack capacity, and
// currency are checked before one atomic commit.
func (executor *Executor) Buy(
	live *campaign.Campaign,
	shopID string,
	itemID string,
	quantity int64,
) error {
	if executor == nil {
		return errors.New("buy shop item: executor is nil")
	}
	if live == nil {
		return errors.New("buy shop item: campaign is nil")
	}
	if quantity <= 0 || quantity > campaign.MaxJSONInteger {
		return fmt.Errorf(
			"buy shop item: quantity must be in [1, %d]",
			campaign.MaxJSONInteger,
		)
	}
	offer, err := executor.shopOffer(shopID, itemID)
	if err != nil {
		return fmt.Errorf("buy shop item: %w", err)
	}
	if !offer.CanBuy {
		return fmt.Errorf(
			"buy shop item: shop %q does not sell item %q",
			shopID,
			itemID,
		)
	}
	cost, err := checkedProduct(int64(offer.BuyPrice), quantity)
	if err != nil {
		return fmt.Errorf("buy shop item: price: %w", err)
	}

	err = live.Transaction(func(state *campaign.State) error {
		if err := executor.requireIdentity(state); err != nil {
			return err
		}
		entry, definition, err := executor.inventoryEntry(state, itemID)
		if err != nil {
			return err
		}
		if quantity > definition.MaxQuantity-entry.Quantity {
			return fmt.Errorf(
				"item %q quantity %d exceeds stack limit %d",
				itemID,
				entry.Quantity+quantity,
				definition.MaxQuantity,
			)
		}
		if state.Currency < cost {
			return fmt.Errorf(
				"currency %d is less than purchase cost %d",
				state.Currency,
				cost,
			)
		}
		entry.Quantity += quantity
		state.Currency -= cost
		return nil
	})
	if err != nil {
		return fmt.Errorf("buy shop item: %w", err)
	}
	return nil
}

// Sell sells an authored shop offer atomically. Selling the final owned copy of
// an equipped item is rejected rather than implicitly changing the loadout.
func (executor *Executor) Sell(
	live *campaign.Campaign,
	shopID string,
	itemID string,
	quantity int64,
) error {
	if executor == nil {
		return errors.New("sell shop item: executor is nil")
	}
	if live == nil {
		return errors.New("sell shop item: campaign is nil")
	}
	if quantity <= 0 || quantity > campaign.MaxJSONInteger {
		return fmt.Errorf(
			"sell shop item: quantity must be in [1, %d]",
			campaign.MaxJSONInteger,
		)
	}
	offer, err := executor.shopOffer(shopID, itemID)
	if err != nil {
		return fmt.Errorf("sell shop item: %w", err)
	}
	if !offer.CanSell {
		return fmt.Errorf(
			"sell shop item: shop %q does not buy item %q",
			shopID,
			itemID,
		)
	}
	proceeds, err := checkedProduct(int64(offer.SellPrice), quantity)
	if err != nil {
		return fmt.Errorf("sell shop item: price: %w", err)
	}

	err = live.Transaction(func(state *campaign.State) error {
		if err := executor.requireIdentity(state); err != nil {
			return err
		}
		entry, _, err := executor.inventoryEntry(state, itemID)
		if err != nil {
			return err
		}
		if entry.Quantity < quantity {
			return fmt.Errorf(
				"owned item %q quantity %d is less than sale quantity %d",
				itemID,
				entry.Quantity,
				quantity,
			)
		}
		remaining := entry.Quantity - quantity
		if remaining == 0 && equipped(state, itemID) {
			return fmt.Errorf(
				"equipped item %q cannot be sold down to zero",
				itemID,
			)
		}
		if proceeds > campaign.MaxJSONInteger-state.Currency {
			return fmt.Errorf(
				"sale proceeds overflow maximum currency %d",
				campaign.MaxJSONInteger,
			)
		}
		entry.Quantity = remaining
		state.Currency += proceeds
		return nil
	})
	if err != nil {
		return fmt.Errorf("sell shop item: %w", err)
	}
	return nil
}

func (executor *Executor) shopOffer(
	shopID string,
	itemID string,
) (gamebuild.ShopOfferRule, error) {
	shop, exists := executor.rules.Shop(shopID)
	if !exists {
		return gamebuild.ShopOfferRule{}, fmt.Errorf(
			"shop %q is not configured",
			shopID,
		)
	}
	for _, offer := range shop.Offers {
		if offer.ItemID == itemID {
			return offer, nil
		}
	}
	return gamebuild.ShopOfferRule{}, fmt.Errorf(
		"shop %q has no offer for item %q",
		shopID,
		itemID,
	)
}

func equipped(state *campaign.State, itemID string) bool {
	for _, entry := range state.Equipment {
		if entry.ItemID == itemID {
			return true
		}
	}
	return false
}

func checkedProduct(value, quantity int64) (int64, error) {
	if value < 0 || quantity <= 0 {
		return 0, errors.New("price and quantity must be non-negative")
	}
	if value != 0 && quantity > campaign.MaxJSONInteger/value {
		return 0, fmt.Errorf(
			"total exceeds maximum JSON-safe integer %d",
			campaign.MaxJSONInteger,
		)
	}
	return value * quantity, nil
}
