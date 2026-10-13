// Prints shippingCost for every combination of inputs. Compile together with
// Sources/Shipping/ShippingCost.swift and compare the output before and after a change.
let regions: [Region] = [.domestic, .canada, .europe, .asia]
for region in regions {
    for weight in [0.5, 2.0, 7.25] {
        for fragile in [false, true] {
            for express in [false, true] {
                for member in [false, true] {
                    let parcel = Parcel(weightKilograms: weight, isFragile: fragile, expressDelivery: express)
                    print(region, weight, fragile, express, member, shippingCost(for: parcel, to: region, isMember: member))
                }
            }
        }
    }
}
