enum Region { case domestic, canada, europe, asia }

struct Parcel {
    var weightKilograms: Double
    var isFragile: Bool
    var expressDelivery: Bool
}

func shippingCost(for parcel: Parcel, to region: Region, isMember: Bool) -> Double {
    var cost: Double
    switch region {
    case .domestic: cost = 5
    case .canada: cost = 12
    case .europe: cost = 20
    case .asia: cost = 25
    }
    if parcel.weightKilograms > 2 {
        cost += (parcel.weightKilograms - 2) * 1.5
    }
    if parcel.isFragile && region != .domestic {
        cost += 8
    } else if parcel.isFragile {
        cost += 4
    }
    if parcel.expressDelivery {
        cost *= 1.5
    }
    if isMember && cost > 10 {
        cost -= 5
    }
    return cost
}
