module Domain.Rooms exposing (rooms)

{-| The hotel's three room categories. In a real app this would come from an API;
here it's a static catalogue so the widget stays self-contained.
-}

import Domain.Types exposing (Room, RoomId(..))


rooms : List Room
rooms =
    [ { id = Standard
      , capacity = 2
      , pricePerNight = { ru = 4500, en = 49 }
      , name = { ru = "Стандарт", en = "Standard" }
      , description =
            { ru = "Уютный номер для двоих с одной двуспальной кроватью."
            , en = "A cosy room for two with one double bed."
            }
      }
    , { id = Comfort
      , capacity = 3
      , pricePerNight = { ru = 6900, en = 75 }
      , name = { ru = "Комфорт", en = "Comfort" }
      , description =
            { ru = "Просторный номер до трёх гостей с зоной отдыха."
            , en = "A spacious room for up to three guests with a lounge area."
            }
      }
    , { id = Family
      , capacity = 5
      , pricePerNight = { ru = 9900, en = 109 }
      , name = { ru = "Семейный", en = "Family" }
      , description =
            { ru = "Большой номер до пяти гостей: две спальни и детская зона."
            , en = "A large room for up to five guests: two bedrooms and a kids area."
            }
      }
    ]
