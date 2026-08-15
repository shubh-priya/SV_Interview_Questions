// code example of singleton class
// A singleton class has just one object possible, it is useful when a single instance of class is to be shared b/w multiple components for data logging, tracking, config setting. It is created at compile time and is a static object.

class singleton;
  static singleton instance_h= null;
  int config_value=0;

  protected function void new ();
    config_value =0;
  endfunction
  static funtion singleton get_config_instance();
  if(instance_h==null)
    instance =new();
  else return instance_h;
  endfunction
  function void set_config(int value);
    config_value=value;
  endfunction
endclass
