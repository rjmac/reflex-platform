package systems.obsidian;

import java.lang.reflect.Method;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.BroadcastReceiver;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.Bundle;
import android.util.Log;
import android.view.ViewGroup.LayoutParams;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import java.util.concurrent.SynchronousQueue;
import android.view.View;

public class HaskellActivity extends Activity {
  public native int haskellStartMain(SynchronousQueue<Long> setCallbacks);
  public native void haskellOnCreate(long callbacks);
  public native void haskellOnStart(long callbacks);
  public native void haskellOnResume(long callbacks);
  public native void haskellOnPause(long callbacks);
  public native void haskellOnStop(long callbacks);
  public native void haskellOnDestroy(long callbacks);
  public native void haskellOnRestart(long callbacks);
  public native void haskellOnNewIntent(long callbacks, String intent, String intentdata);

  // Apparently 'long' is the right way to store a C pointer in Java
  // See https://stackoverflow.com/questions/337268/what-is-the-correct-way-to-store-a-native-pointer-inside-a-java-object
  final long callbacks;

  static {
    System.loadLibrary("HaskellActivity");
  }

  public HaskellActivity() throws InterruptedException {
    final SynchronousQueue<Long> setCallbacks = new SynchronousQueue<Long>();
    new Thread() {
      public void run() {
        final int exitCode = haskellStartMain(setCallbacks);
        Log.d("HaskellActivity", String.format("Haskell main action exited with status %d", exitCode));
        try {
          // Since Haskell's main has exited, it won't call mainStarted.
          // Instead, we unblock the main thread here.
          //TODO: If continueWithCallbacks has already been called, is this safe?
          setCallbacks.put(0L); //TODO: Always call finish() if we hit this
        } catch(InterruptedException e) {
          //TODO: Should we do something with this?
        }
      }
    }.start();
    callbacks = setCallbacks.take();
  }

  // This can be called by the Haskell application to unblock the construction
  // of the HaskellActivity and proced with the given callbacks

  // NOTE: This shouldn't be an instance method, because it must be called *before*
  // the constructor returns (it *causes* the constructor to return).
  // 'callbacks' should never be 0
  private static void continueWithCallbacks(SynchronousQueue<Long> setCallbacks, long callbacks) {
    try {
      setCallbacks.put(callbacks);
    } catch(InterruptedException e) {
      Log.d("HaskellActivity", "setting callbacks interrupted");
      //TODO: Should we do something with this?
    }
  }

  @Override
  public void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);

    // We can't call finish() in the constructor, as it will have no effect, so
    // we call it here whenever we reach this code without having hit
    // 'continueWithCallbacks'
    if(callbacks == 0) {
      finish();
    } else {
      haskellOnCreate(callbacks); //TODO: Pass savedInstanceState as well
    }
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
  }

  @Override
  public void onStart() {
    super.onStart();
    if(callbacks != 0) {
      haskellOnStart(callbacks);
    }
  }

  @Override
  public void onResume() {
    super.onResume();
    if(callbacks != 0) {
      haskellOnResume(callbacks);
    }
  }

  @Override
  public void onPause() {
    super.onPause();
    if(callbacks != 0) {
      haskellOnPause(callbacks);
    }
  }

  @Override
  public void onStop() {
    super.onStop();
    if(callbacks != 0) {
      haskellOnStop(callbacks);
    }
  }

  @Override
  public void onDestroy() {
    super.onDestroy();
    if(callbacks != 0) {
      haskellOnDestroy(callbacks);
    }
    //TODO: Should we call hs_exit somehow here?
    android.os.Process.killProcess(android.os.Process.myPid()); //TODO: Properly handle the process surviving between invocations which means that the Haskell RTS needs to not be initialized twice.
  }

  @Override
  public void onRestart() {
    super.onRestart();
    if(callbacks != 0) {
      haskellOnRestart(callbacks);
    }
  }

  @Override
  public void onNewIntent(Intent intent) {
    super.onNewIntent(intent);
    if(callbacks != 0 && intent != null && intent.getData() != null && intent.getAction() != null) {
      haskellOnNewIntent(callbacks, intent.getAction(), intent.getDataString()); //TODO: Use a more canonical way of passing this data - i.e. pass the Intent and let the Haskell side get the data out with JNI
    }
  }

  @Override
  public void onWindowFocusChanged(boolean hasFocus) {
    super.onWindowFocusChanged(hasFocus);
    View v = getCurrentFocus();
    if(v != null) {
        v.setSystemUiVisibility(
              View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                      | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                      | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                      | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                      | View.SYSTEM_UI_FLAG_FULLSCREEN
                      | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
    }
  }

  private Object requestPermissionsResultCallbackObject = null;
  private Method requestPermissionsResultCallbackMethod = null;
  private Object batteryStatusCallbackObject = null;
  private Method batteryStatusCallbackMethod = null;

  public void setOnRequestPermissionsResultCallback(Object cb) {
      try {
          Class<?> cls = cb.getClass();
          requestPermissionsResultCallbackMethod = cls.getMethod("onRequestPermissionsResultCallback", int.class, String[].class, int[].class);
          requestPermissionsResultCallbackObject = cb;
      } catch(Exception e) {
          throw new RuntimeException(e);
      }
  }

  public String setBatteryStatusCallback(Object cb) {
      try {
          Class<?> cls = cb.getClass();
          batteryStatusCallbackMethod = cls.getMethod("onBatteryStatusCallback", boolean.class, float.class);
          batteryStatusCallbackObject = cb;
      } catch(Exception e) {
          throw new RuntimeException(e);
      }

    IntentFilter filter = new IntentFilter(Intent.ACTION_BATTERY_CHANGED);
    Intent intent = registerReceiver(powerReceiver, filter);

    int status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
    boolean charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
        status == BatteryManager.BATTERY_STATUS_FULL;

    int level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
    int scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1);

    float pct = level / (float) scale;

    return "{\"charging\": " + charging + ", \"percent\": " + pct + "}";
  }

  @Override
  public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
      boolean result = false;
      if(requestPermissionsResultCallbackObject != null) {
          try {
              result = (Boolean) requestPermissionsResultCallbackMethod.
                  invoke(requestPermissionsResultCallbackObject, requestCode, permissions, grantResults);
          } catch(RuntimeException e) {
              throw e;
          } catch(Exception e) {
              throw new RuntimeException(e);
          }
      }
      if(!result) super.onRequestPermissionsResult(requestCode, permissions, grantResults);
  }

  private class PowerReceiver extends BroadcastReceiver {
      @Override
      public void onReceive(Context context, Intent intent) {
          go(intent);
      }

      public void go(Intent intent) {
          int status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
          boolean charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
              status == BatteryManager.BATTERY_STATUS_FULL;

          int level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
          int scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1);

          float pct = level / (float) scale;

          if(batteryStatusCallbackObject != null) {
              try {
                  batteryStatusCallbackMethod.invoke(batteryStatusCallbackObject, charging, pct);
              } catch(RuntimeException e) {
                  throw e;
              } catch(Exception e) {
                  throw new RuntimeException(e);
              }
          }
      }
  };

  private final PowerReceiver powerReceiver = new PowerReceiver();
}
