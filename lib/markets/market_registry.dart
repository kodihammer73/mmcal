import '../engine/engine.dart';
import '../config/settings.dart';
import 'malaysia.dart';
import 'singapore.dart';
import 'hongkong.dart';
import 'united_states.dart';
import 'simple_markets.dart';

List<Market> getAllMarkets(SettingsManager s) {
  return [
    MalaysiaMarket(s),
    SingaporeMarket(s),
    HongKongMarket(s),
    UnitedStatesMarket(s),
    ThailandMarket(s),
    IndonesiaMarket(s),
    UnitedKingdomMarket(s),
    AustraliaMarket(s),
    JapanMarket(s),
    CanadaMarket(s),
    GermanyMarket(s),
  ];
}