"""Local-only portable product and Sonar tooling coverage suite."""
import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
suite=unittest.defaultTestLoader.loadTestsFromNames(['test_packaging','test_windows_shutdown_export','test_windows_steam_debug_tools','sonar_tooling_test','native_coverage_test'])
raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
