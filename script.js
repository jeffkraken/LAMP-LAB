// script.js - used by LAMP LABS website

function getMember() {
    const encodedUser = "dG9kZHQ=";
    const encodedPass = "UEBzc3cwcmQ=";

    return {
        username: atob(encodedUser),
        password: atob(encodedPass)
    };
}
