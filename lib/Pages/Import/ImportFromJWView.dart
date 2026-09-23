import 'dart:io';
import 'package:flutter/services.dart';
import '../../Components/Dialog.dart';
import '../../Components/TransBgTextButton.dart';
import '../../generated/l10n.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import '../../Resources/Constant.dart';
import '../../Components/Toast.dart';
import '../../Resources/Url.dart';

import '../../Utils/JwCredentialVault.dart';
import 'ImportFromJWPresenter.dart';
import 'dart:math';

class ImportFromJWView extends StatefulWidget {
  final JwCredentialVault? credentials;
  final ImportFromJWPresenter? presenter;

  const ImportFromJWView({Key? key, this.credentials, this.presenter})
      : super(key: key);

  @override
  _ImportFromJWViewState createState() => _ImportFromJWViewState();
}

class _ImportFromJWViewState extends State<ImportFromJWView> {
  late final ImportFromJWPresenter _presenter;

  final TextEditingController _usrController = TextEditingController();
  final TextEditingController _pwdController = TextEditingController();
  final TextEditingController _captchaController = TextEditingController();
  final FocusNode usrTextFieldNode = FocusNode();
  final FocusNode pwdTextFieldNode = FocusNode();
  final FocusNode captchaTextFieldNode = FocusNode();

  bool _checkboxSelected = false;
  double randomNumForCaptcha = Random().nextDouble();
  late final JwCredentialVault _credentials;

  @override
  void initState() {
    super.initState();
    _credentials = widget.credentials ?? JwCredentialVault.platform();
    _presenter = widget.presenter ?? ImportFromJWPresenter();
    _getUserInfo();
  }

  Future<void> _getUserInfo() async {
    try {
      final saved = await _credentials.load();
      if (!mounted) return;
      if (saved == null) {
        setState(() => _checkboxSelected = false);
        return;
      }
      setState(() {
        _checkboxSelected = true;
        _usrController.text = saved.username;
        _pwdController.text = saved.password;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkboxSelected = false);
    }
  }

  Future<void> _saveUserInfo() async {
    await _credentials.save(
      _usrController.value.text.toString(),
      _pwdController.value.text.toString(),
    );
  }

  Future<void> _clearUserInfo() => _credentials.delete();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(S.of(context).import_from_JW_title),
        ),
        body: Builder(builder: (BuildContext context) {
          return Container(
              width: double.infinity,
              margin: const EdgeInsets.all(10),
              child: Column(children: <Widget>[
                // MaterialBanner(
                //   forceActionsBelow: true,
                //   content: FittedBox(
                //       fit: BoxFit.scaleDown,
                //       alignment: Alignment.centerLeft,
                //       child: Text(S.of(context).import_banner,
                //           style: const TextStyle(color: Colors.white))),
                //   backgroundColor: Theme.of(context).primaryColor,
                //   actions: [
                //     TextButton(
                //         style: TextButton.styleFrom(
                //             foregroundColor: Colors.white,
                //             backgroundColor: Theme.of(context).primaryColor),
                //         child: Text(S.of(context).import_banner_action),
                //         onPressed: () => launch(Url.URL_NJU_VPN))
                //   ],
                // ),
                Container(
                  padding: const EdgeInsets.all(5),
                ),
                TextField(
                  controller: _usrController,
                  decoration: InputDecoration(
                    focusedBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: Theme.of(context).primaryColor),
                    ),
                    icon: const Icon(Icons.account_circle),
                    hintText: S.of(context).username,
                  ),
                  onEditingComplete: () =>
                      FocusScope.of(context).requestFocus(pwdTextFieldNode),
                ),
                Container(
                  padding: const EdgeInsets.all(5),
                ),
                TextField(
                  controller: _pwdController,
                  decoration: InputDecoration(
                    focusedBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: Theme.of(context).primaryColor),
                    ),
                    icon: const Icon(Icons.lock),
                    hintText: S.of(context).password,
                  ),
                  obscureText: true,
                  onEditingComplete: () =>
                      FocusScope.of(context).requestFocus(captchaTextFieldNode),
                ),
                Container(
                  padding: const EdgeInsets.all(5),
                ),
                Row(children: <Widget>[
                  Flexible(
                      child: TextField(
                    controller: _captchaController,
                    decoration: InputDecoration(
                      focusedBorder: UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: Theme.of(context).primaryColor),
                      ),
                      icon: const Icon(Icons.code),
                      hintText: S.of(context).captcha,
                    ),
                  )),
                  Container(
                    padding: const EdgeInsets.all(5),
                    child: InkWell(
                      child: FutureBuilder(
                          future: _presenter.getCaptcha(randomNumForCaptcha),
                          builder: (BuildContext context,
                              AsyncSnapshot<Image> image) {
                            if (image.hasData) {
                              return image.data!;
                            } else {
                              return Container();
                            }
                          }),
                      onTap: () => setState(() {
                        randomNumForCaptcha = Random().nextDouble();
                      }),
                    ),
                  ),
                  Container(
                      padding: const EdgeInsets.all(5),
                      child: InkWell(
                        child: Text(
                          S.of(context).tap_to_refresh,
                          style: TextStyle(
                              color: Theme.of(context).brightness ==
                                      Brightness.light
                                  ? Theme.of(context).primaryColor
                                  : Colors.white),
                        ),
                        onTap: () => setState(() {
                          randomNumForCaptcha = Random().nextDouble();
                        }),
                      ))
                ]),
                Row(
                  children: <Widget>[
                    SizedBox(
                        height: 44.0,
                        width: 24.0,
                        child: Checkbox(
                          value: _checkboxSelected,
                          checkColor:
                              Theme.of(context).brightness == Brightness.light
                                  ? Colors.white
                                  : Colors.black,
                          onChanged: (value) async {
                            final selected = value ?? false;
                            if (!selected) {
                              try {
                                await _clearUserInfo();
                              } catch (_) {
                                if (!mounted) return;
                                Toast.showToast('暂时无法删除已保存的密码，请重试', context);
                                return;
                              }
                            }
                            if (!mounted) return;
                            setState(() => _checkboxSelected = selected);
                          },
                        )),
                    const Padding(
                      padding: EdgeInsets.only(left: 10),
                    ),
                    Text(S.of(context).remember_password),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(5),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                      child: Text(S.of(context).import),
                      onPressed: () async {
                        try {
                          if (_checkboxSelected) {
                            await _saveUserInfo();
                          } else {
                            await _clearUserInfo();
                          }
                        } catch (_) {
                          Toast.showToast(
                              _checkboxSelected
                                  ? '密码未能写入安全存储，请重试'
                                  : '暂时无法删除已保存的密码，请重试',
                              context);
                          return;
                        }
                        if (_usrController.value.text.toString() == 'admin' &&
                            _pwdController.value.text.toString() == 'admin') {
                          await _presenter.getDemoClasses(context);
                          Toast.showToast(
                              S.of(context).class_parse_toast_success, context);
                          Navigator.of(context).pop(true);
                          return;
                        }
                        int status = await _presenter.login(
                            _usrController.value.text.toString(),
                            _pwdController.value.text.toString(),
                            _captchaController.value.text.toString());
                        if (status == Constant.PASSWORD_ERROR) {
                          Toast.showToast(
                              S.of(context).password_error_toast, context);
                          setState(() {
                            _pwdController.clear();
                            randomNumForCaptcha = Random().nextDouble();
                          });
                        } else if (status == Constant.CAPTCHA_ERROR) {
                          Toast.showToast(
                              S.of(context).captcha_error_toast, context);

                          setState(() {
                            randomNumForCaptcha = Random().nextDouble();
                          });
                        } else if (status == Constant.USERNAME_ERROR) {
                          Toast.showToast(
                              S.of(context).username_error_toast, context);
                        } else if (status == Constant.LOGIN_CORRECT) {
                          bool isSuccess = await _presenter.getClasses(context);
                          if (!isSuccess) {
                            Toast.showToast(
                                S.of(context).class_parse_error_toast, context);
                          } else {
                            Toast.showToast(
                                S.of(context).class_parse_toast_success,
                                context);
                          }
                          Navigator.of(context).pop(true);
                        } else {
                          // Toast.showToast(
                          //     S.of(context).class_parse_toast_fail, context);
                          showDialog<String>(
                              barrierDismissible: false,
                              context: context,
                              builder: (BuildContext context) {
                                return MDialog(
                                  S.of(context).parse_error_dialog_title,
                                  Text(S
                                      .of(context)
                                      .parse_error_dialog_content("102")),
                                  overrideActions: <Widget>[
                                    Container(
                                        alignment: Alignment.centerRight,
                                        child: TransBgTextButton(
                                            color: Theme.of(context)
                                                        .brightness ==
                                                    Brightness.light
                                                ? Theme.of(context).primaryColor
                                                : Colors.white,
                                            child: Text(S
                                                .of(context)
                                                .parse_error_dialog_add_group),
                                            onPressed: () async {
                                              await Clipboard.setData(
                                                  const ClipboardData(
                                                      text: "102"));
                                              if (Platform.isIOS) {
                                                launch(Url.QQ_GROUP_APPLE_URL);
                                              } else if (Platform.isAndroid) {
                                                launch(
                                                    Url.QQ_GROUP_ANDROID_URL);
                                              } else if (Platform
                                                      .operatingSystem ==
                                                  'ohos') {
                                                launch(Url.QQ_GROUP_OHOS_URL);
                                              }
                                              Navigator.of(context).pop();
                                            })),
                                    Container(
                                        alignment: Alignment.centerRight,
                                        child: TransBgTextButton(
                                            color: Colors.grey,
                                            child: Text(
                                                S
                                                    .of(context)
                                                    .parse_error_dialog_other_ways,
                                                style: const TextStyle(
                                                    color: Colors.grey)),
                                            onPressed: () async {
                                              Navigator.of(context).pop();
                                              Navigator.of(context).pop();
                                            }))
                                  ],
                                );
                              });
                          setState(() {
                            randomNumForCaptcha = Random().nextDouble();
                          });
                        }
                      }),
                )
              ]));
        }));
  }
}
