import React from "react";
import { Button } from "@base-ui/react/button";
import { Checkbox } from "@base-ui/react/checkbox";
import { Input } from "@base-ui/react/input";

export function button(className, onClick, children) {
  return React.createElement(Button, { className, onClick }, ...children);
}

export function submitButton(className, children) {
  return React.createElement(Button, { className, type: "submit" }, ...children);
}

export function textInput(className, value, placeholder, onValueChange) {
  return React.createElement(Input, {
    className,
    value,
    placeholder,
    onValueChange,
  });
}

export function checkbox(className, checked, label, onCheckedChange) {
  return React.createElement(
    Checkbox.Root,
    {
      "aria-label": label,
      checked,
      className,
      onCheckedChange: () => onCheckedChange(),
    },
    React.createElement(Checkbox.Indicator, { className: "checkbox-indicator" }),
  );
}
